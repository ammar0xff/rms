import 'package:sembast/sembast.dart';
import 'package:uuid/uuid.dart';

import '../../core/config/app_version.dart';
import '../../core/logging/app_logger.dart';
import '../../domain/models/approval_request.dart';
import '../../domain/models/audit_entry.dart';
import '../../domain/models/payment.dart';
import '../local/audit_log.dart';
import '../sync/record_mirror.dart';
import '../local/local_database.dart';
import '../local/local_stores.dart';
import '../local/outbox/outbox_entry.dart';
import '../local/outbox/outbox_status.dart';
import '../local/outbox/outbox_store.dart';
import 'approval_repository.dart';

/// Local-first refund approvals.
///
/// A refund request only writes an approval row, an outbox command and an audit
/// event. The correcting (negative) payment is written in the same transaction
/// as the approval decision, so a request can never become money without a
/// recorded decision.
class LocalApprovalRepository implements ApprovalRepository {
  LocalApprovalRepository(
    this._db, {
    OutboxStore? outbox,
    AuditLog? audit,
    Uuid? uuid,
    DateTime Function()? clock,
    RecordMirror? mirror,
  })  : _outbox = outbox ?? OutboxStore(_db),
        _audit = audit ?? AuditLog(_db),
        _uuid = uuid ?? const Uuid(),
        _clock = clock ?? DateTime.now,
        _mirror = mirror;

  final LocalDatabase _db;
  final OutboxStore _outbox;
  final AuditLog _audit;
  final Uuid _uuid;
  final DateTime Function() _clock;

  /// Best-effort data mirror (see [RecordMirror]). Null outside Firebase
  /// mode, where there is nowhere to mirror to.
  final RecordMirror? _mirror;

  @override
  Future<ApprovalRequest> requestRefund({
    required String orderLocalId,
    required String orderRef,
    required double amount,
    required String reason,
    PaymentMethod method = PaymentMethod.cash,
    String requestedBy = 'cashier',
    bool createdOffline = false,
  }) async {
    final id = _uuid.v4();
    final now = _clock();
    final request = ApprovalRequest(
      id: id,
      kind: ApprovalKind.refund,
      orderLocalId: orderLocalId,
      orderRef: orderRef,
      amount: amount,
      reason: reason,
      requestedAt: now,
      method: method,
      requestedBy: requestedBy,
      createdOffline: createdOffline,
    );
    await _db.transaction((txn) async {
      await LocalStores.approvals.record(id).put(txn, request.toRecord());
      await _outbox.append(
        txn,
        _entry(
          entityType: 'approval',
          entityId: id,
          operationType: 'requestRefund',
          createdAt: now,
          payload: {
            'id': id,
            'kind': request.kind.name,
            'orderRef': orderRef,
            'amount': amount,
            'method': method.name,
          },
        ),
      );
      await _audit.append(
        txn,
        AuditEntry(
          id: _uuid.v4(),
          action: AuditAction.requestApproval,
          entityType: 'approval',
          entityId: id,
          summary: 'طلب استرداد ${amount.toStringAsFixed(2)} · $reason',
          at: now,
          amount: amount,
          createdOffline: createdOffline,
        ),
      );
    });
    AppLogger.info('Refund request $id queued for approval.');
    return request;
  }

  @override
  Future<List<ApprovalRequest>> listRequests() async {
    final snapshots = await LocalStores.approvals.find(_db.db);
    final requests =
        snapshots.map((s) => ApprovalRequest.fromRecord(s.value)).toList()
          ..sort((a, b) => a.requestedAt.compareTo(b.requestedAt));
    return requests;
  }

  @override
  Future<ApprovalRequest?> decide(
    String id, {
    required bool approved,
    String decidedBy = 'manager',
  }) async {
    final now = _clock();
    ApprovalRequest? decided;
    await _db.transaction((txn) async {
      final record = LocalStores.approvals.record(id);
      final existing = await record.get(txn);
      if (existing == null) return;
      final request = ApprovalRequest.fromRecord(existing);
      if (!request.isPending) {
        // Already decided — idempotent, never double-post.
        decided = request;
        return;
      }

      request.status =
          approved ? ApprovalStatus.approved : ApprovalStatus.rejected;
      request.decidedBy = decidedBy;
      request.decidedAt = now;
      request.syncStatus = SyncStatus.pendingSync;
      await record.put(txn, request.toRecord());
      await _outbox.append(
        txn,
        _entry(
          entityType: 'approval',
          entityId: id,
          operationType: approved ? 'approveRefund' : 'rejectRefund',
          createdAt: now,
          payload: {
            'id': id,
            'kind': request.kind.name,
            'orderRef': request.orderRef,
            'amount': request.amount,
            'approved': approved,
            'decidedBy': decidedBy,
          },
        ),
      );

      if (approved && request.kind == ApprovalKind.refund) {
        await _postRefund(txn, request, now);
      }

      await _audit.append(
        txn,
        AuditEntry(
          id: _uuid.v4(),
          action: approved ? AuditAction.approveRequest : AuditAction.rejectRequest,
          entityType: 'approval',
          entityId: id,
          summary: '${approved ? 'اعتماد' : 'رفض'} طلب ${request.orderRef}',
          at: now,
          amount: request.amount,
          createdOffline: true,
        ),
      );
      decided = request;
    });
    return decided;
  }

  /// Writes the correcting negative payment and its own outbox command.
  Future<void> _postRefund(
    Transaction txn,
    ApprovalRequest request,
    DateTime now,
  ) async {
    final paymentId = _uuid.v4();
    final payment = PaymentModel(
      id: paymentId,
      orderLocalId: request.orderLocalId,
      orderRef: request.orderRef,
      amount: -request.amount,
      method: request.method,
      createdAt: now,
      createdOffline: request.createdOffline,
    );
    await LocalStores.payments.record(paymentId).put(txn, payment.toRecord());
    await _outbox.append(
      txn,
      _entry(
        entityType: 'payment',
        entityId: paymentId,
        operationType: 'recordPayment',
        createdAt: now,
        payload: {
          'id': paymentId,
          'orderLocalId': request.orderLocalId,
          'orderRef': request.orderRef,
          'amount': -request.amount,
          'method': request.method.name,
        },
      ),
    );
    await _audit.append(
      txn,
      AuditEntry(
        id: _uuid.v4(),
        action: AuditAction.recordRefund,
        entityType: 'payment',
        entityId: paymentId,
        summary: 'استرداد معتمد للطلب ${request.orderRef}',
        at: now,
        amount: -request.amount,
        createdOffline: request.createdOffline,
      ),
    );
  }

  /// Marks a request as synced once its command is acknowledged.
  Future<void> applySynced(OutboxEntry entry) async {
    if (entry.entityType != 'approval') return;
    final record = LocalStores.approvals.record(entry.entityId);
    final existing = await record.get(_db.db);
    if (existing == null) return;
    final request = ApprovalRequest.fromRecord(existing);
    if (!await _outbox.hasOutstandingFor(entityType: 'approval', entityId: entry.entityId)) {
      request.syncStatus = SyncStatus.synced;
    }
    await record.put(_db.db, request.toRecord());
    await mirrorRecord(_mirror, 
      entityType: 'approval',
      entityId: entry.entityId,
      snapshot: request.toRecord(),
    );
  }

  /// Writes pre-existing requests without queueing commands (demo seeding).
  Future<void> seedApprovals(List<ApprovalRequest> requests) async {
    if (requests.isEmpty) return;
    await _db.transaction((txn) async {
      for (final request in requests) {
        await LocalStores.approvals
            .record(request.id)
            .put(txn, request.toRecord());
      }
    });
    AppLogger.info('Seeded ${requests.length} demo approval requests.');
  }

  OutboxEntry _entry({
    required String entityType,
    required String entityId,
    required String operationType,
    required DateTime createdAt,
    required Map<String, Object?> payload,
  }) =>
      OutboxEntry(
        operationId: _uuid.v4(),
        entityType: entityType,
        entityId: entityId,
        operationType: operationType,
        payload: Map<String, dynamic>.from(payload),
        schemaVersion: AppVersion.localSchemaVersion,
        idempotencyKey: _uuid.v4(),
        createdAt: createdAt,
      );
}

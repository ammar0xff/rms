import 'package:sembast/sembast.dart';
import 'package:uuid/uuid.dart';

import '../../core/config/app_version.dart';
import '../../core/logging/app_logger.dart';
import '../../domain/models/audit_entry.dart';
import '../../domain/models/cash_session.dart';
import '../../domain/models/collection.dart';
import '../../domain/models/order_type.dart';
import '../../domain/models/payment.dart';
import '../../domain/money.dart';
import '../local/audit_log.dart';
import '../sync/record_mirror.dart';
import '../local/local_database.dart';
import '../local/local_stores.dart';
import '../local/outbox/outbox_entry.dart';
import '../local/outbox/outbox_status.dart';
import '../local/outbox/outbox_store.dart';
import 'cash_session_repository.dart';

/// Local-first cashier sessions.
///
/// The drawer total is derived from the cash payments and delivery collections
/// recorded on this device, so a session can be counted and closed offline. The
/// close command is queued for the backend and the session is only marked synced
/// once that command is acknowledged.
class LocalCashSessionRepository implements CashSessionRepository {
  LocalCashSessionRepository(
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
  Future<List<CashSession>> listSessions() async {
    final snapshots = await LocalStores.cashSessions.find(_db.db);
    final sessions = <CashSession>[];
    for (final s in snapshots) {
      try {
        sessions.add(CashSession.fromRecord(s.value));
      } catch (e) {
        AppLogger.warn('Skipping corrupted cash session record ${s.key}: $e');
      }
    }
    sessions.sort((a, b) => a.openedAt.compareTo(b.openedAt));
    return sessions;
  }

  @override
  Future<CashSession?> currentSession() async {
    final snapshots = await LocalStores.cashSessions.find(
      _db.db,
      finder: Finder(
        filter: Filter.equals('status', CashSessionStatus.open.name),
      ),
    );
    if (snapshots.isEmpty) return null;
    final sessions = <CashSession>[];
    for (final s in snapshots) {
      try {
        sessions.add(CashSession.fromRecord(s.value));
      } catch (e) {
        AppLogger.warn('Skipping corrupted cash session record ${s.key}: $e');
      }
    }
    if (sessions.isEmpty) return null;
    sessions.sort((a, b) => b.openedAt.compareTo(a.openedAt));
    return sessions.first;
  }

  @override
  Stream<CashSession?> watchCurrentSession() {
    return LocalStores.cashSessions
        .query(
          finder: Finder(
            filter: Filter.equals('status', CashSessionStatus.open.name),
          ),
        )
        .onSnapshots(_db.db)
        .map((snapshots) {
      if (snapshots.isEmpty) return null;
      final sessions = <CashSession>[];
      for (final s in snapshots) {
        try {
          sessions.add(CashSession.fromRecord(s.value));
        } catch (_) {}
      }
      if (sessions.isEmpty) return null;
      sessions.sort((a, b) => b.openedAt.compareTo(a.openedAt));
      return sessions.first;
    });
  }

  @override
  Future<CashSession> openSession({
    required double openingFloat,
    String? cashierUid,
    String? cashierName,
    String? branchId,
    String? branchName,
    bool createdOffline = false,
  }) async {
    final now = _clock();
    final id = _uuid.v4();
    final session = CashSession(
      id: id,
      openedAt: now,
      openingFloat: openingFloat,
      cashierUid: cashierUid,
      cashierName: cashierName,
      branchId: branchId,
      branchName: branchName,
      createdOffline: createdOffline,
    );
    await _db.transaction((txn) async {
      final open = await LocalStores.cashSessions.find(
        txn,
        finder: Finder(
          filter: Filter.equals('status', CashSessionStatus.open.name),
        ),
      );
      if (open.isNotEmpty) return; // a session is already open
      await LocalStores.cashSessions.record(id).put(txn, session.toRecord());
      await _outbox.append(
        txn,
        _entry(
          entityId: id,
          operationType: 'openCashSession',
          createdAt: now,
          payload: {
            'id': id,
            'openingFloat': openingFloat,
            'openedAt': now.toIso8601String(),
            if (cashierUid != null) 'cashierUid': cashierUid,
            if (cashierName != null) 'cashierName': cashierName,
            if (branchId != null) 'branchId': branchId,
            if (branchName != null) 'branchName': branchName,
          },
        ),
      );
      await _audit.append(
        txn,
        AuditEntry(
          id: _uuid.v4(),
          action: AuditAction.openCashSession,
          entityType: 'cashSession',
          entityId: id,
          summary:
              'فتح جلسة برأس مال ${openingFloat.toStringAsFixed(2)}${cashierName != null ? ' بواسطة $cashierName' : ''}${branchName != null ? ' (فرع $branchName)' : ''}',
          at: now,
          actor: cashierName ?? cashierUid ?? 'system',
          amount: openingFloat,
          createdOffline: createdOffline,
        ),
      );
    });
    final result = await currentSession() ?? session;
    await mirrorRecord(
      _mirror,
      entityType: 'cashSession',
      entityId: result.id,
      snapshot: result.toRecord(),
    );
    return result;
  }

  @override
  Future<CashSession> closeSession(
    String id, {
    required double countedCash,
    String? note,
    String? cashierUid,
    String? cashierName,
  }) async {
    final now = _clock();
    CashSession? closed;
    await _db.transaction((txn) async {
      final record = LocalStores.cashSessions.record(id);
      final existing = await record.get(txn);
      if (existing == null) return;
      final session = CashSession.fromRecord(existing);
      if (!session.isOpen) {
        closed = session;
        return;
      }
      final expected = roundMoney(await _expectedCash(txn, session, now));
      final variance = roundMoney(countedCash - expected);
      session.closedAt = now;
      session.countedCash = countedCash;
      session.expectedCash = expected;
      session.status = CashSessionStatus.closed;
      session.note = note;
      session.syncStatus = SyncStatus.pendingSync;
      await record.put(txn, session.toRecord());
      await _outbox.append(
        txn,
        _entry(
          entityId: id,
          operationType: 'closeCashSession',
          createdAt: now,
          payload: {
            'id': id,
            'countedCash': countedCash,
            'expectedCash': expected,
            'variance': variance,
            if (cashierUid != null || session.cashierUid != null)
              'cashierUid': cashierUid ?? session.cashierUid,
            if (cashierName != null || session.cashierName != null)
              'cashierName': cashierName ?? session.cashierName,
          },
        ),
      );
      final closingActor =
          cashierName ?? session.cashierName ?? cashierUid ?? session.cashierUid ?? 'system';
      await _audit.append(
        txn,
        AuditEntry(
          id: _uuid.v4(),
          action: AuditAction.closeCashSession,
          entityType: 'cashSession',
          entityId: id,
          summary:
              'إغلاق جلسة · متوقع ${expected.toStringAsFixed(2)} · فرق ${variance.toStringAsFixed(2)}${closingActor != 'system' ? ' بواسطة $closingActor' : ''}',
          at: now,
          actor: closingActor,
          amount: variance,
          createdOffline: true,
        ),
      );
      closed = session;
    });
    final result = closed;
    if (result == null) {
      throw StateError('cash session $id not found');
    }
    await mirrorRecord(
      _mirror,
      entityType: 'cashSession',
      entityId: id,
      snapshot: result.toRecord(),
    );
    return result;
  }

  @override
  Future<double> expectedCash(CashSession session) => _db.transaction(
        (txn) => _expectedCash(txn, session, session.closedAt ?? _clock()),
      );

  Future<double> _expectedCash(
    Transaction txn,
    CashSession session,
    DateTime asOf,
  ) async {
    var total = session.openingFloat;
    final openedUtc = session.openedAt.toUtc();
    final asOfUtc = asOf.toUtc();

    final allPayments = await LocalStores.payments.find(
      txn,
      finder: Finder(
        filter: Filter.equals('method', PaymentMethod.cash.name),
      ),
    );
    for (final snapshot in allPayments) {
      final map = snapshot.value;
      // Skip if payment is for a delivery order (delivery cash enters drawer only via settled collections)
      final orderLocalId = map['orderLocalId'] as String?;
      if (orderLocalId != null) {
        final orderRecord = await LocalStores.orders.record(orderLocalId).get(txn);
        if (orderRecord != null && orderRecord['orderType'] == OrderType.delivery.name) {
          continue;
        }
      }
      final createdAtRaw = map['createdAt'];
      if (createdAtRaw == null) continue;
      final createdAt = DateTime.tryParse(createdAtRaw.toString());
      if (createdAt == null) continue;
      final createdUtc = createdAt.toUtc();
      if (!createdUtc.isBefore(openedUtc) && !createdUtc.isAfter(asOfUtc)) {
        total += (map['amount'] as num?)?.toDouble() ?? 0.0;
      }
    }

    final allCollections = await LocalStores.collections.find(
      txn,
      finder: Finder(
        filter: Filter.equals('method', PaymentMethod.cash.name),
      ),
    );
    for (final snapshot in allCollections) {
      final map = snapshot.value;
      // Delivery cash enters drawer ONLY when custody has been handed over and settled
      if (map['settlementStatus'] != SettlementStatus.settled.name) {
        continue;
      }
      final settledAtRaw = map['settledAt'] ?? map['collectedAt'];
      if (settledAtRaw == null) continue;
      final settledAt = DateTime.tryParse(settledAtRaw.toString());
      if (settledAt == null) continue;
      final settledUtc = settledAt.toUtc();
      if (!settledUtc.isBefore(openedUtc) && !settledUtc.isAfter(asOfUtc)) {
        total += (map['amount'] as num?)?.toDouble() ?? 0.0;
      }
    }

    return total;
  }

  /// Marks a session as synced once its command is acknowledged.
  Future<void> applySynced(OutboxEntry entry) async {
    if (entry.entityType != 'cashSession') return;
    final record = LocalStores.cashSessions.record(entry.entityId);
    final existing = await record.get(_db.db);
    if (existing == null) return;
    final session = CashSession.fromRecord(existing);
    if (!await _outbox.hasOutstandingFor(entityType: 'cashSession', entityId: entry.entityId)) {
      session.syncStatus = SyncStatus.synced;
    }
    await record.put(_db.db, session.toRecord());
    await mirrorRecord(_mirror, 
      entityType: 'cashSession',
      entityId: entry.entityId,
      snapshot: session.toRecord(),
    );
  }

  /// Writes pre-existing sessions without queueing commands (demo seeding).
  Future<void> seedSessions(List<CashSession> sessions) async {
    if (sessions.isEmpty) return;
    await _db.transaction((txn) async {
      for (final session in sessions) {
        await LocalStores.cashSessions
            .record(session.id)
            .put(txn, session.toRecord());
      }
    });
    AppLogger.info('Seeded ${sessions.length} demo cash sessions.');
  }

  OutboxEntry _entry({
    required String entityId,
    required String operationType,
    required DateTime createdAt,
    required Map<String, Object?> payload,
  }) =>
      OutboxEntry(
        operationId: _uuid.v4(),
        entityType: 'cashSession',
        entityId: entityId,
        operationType: operationType,
        payload: Map<String, dynamic>.from(payload),
        schemaVersion: AppVersion.localSchemaVersion,
        idempotencyKey: _uuid.v4(),
        createdAt: createdAt,
      );
}

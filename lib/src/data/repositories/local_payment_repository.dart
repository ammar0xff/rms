import 'package:sembast/sembast.dart';
import 'package:uuid/uuid.dart';

import '../../core/config/app_version.dart';
import '../../core/logging/app_logger.dart';
import '../../domain/models/payment.dart';
import '../local/local_database.dart';
import '../local/local_stores.dart';
import '../local/outbox/outbox_entry.dart';
import '../local/outbox/outbox_status.dart';
import '../local/outbox/outbox_store.dart';
import 'payment_repository.dart';

/// Append-only payment log backed by the on-device store.
///
/// [recordPayment] commits the payment and its outbox entry in one transaction,
/// so a crash can never leave a collected payment without a sync command.
class LocalPaymentRepository implements PaymentRepository {
  LocalPaymentRepository(
    this._db, {
    OutboxStore? outbox,
    Uuid? uuid,
    DateTime Function()? clock,
  })  : _outbox = outbox ?? OutboxStore(_db),
        _uuid = uuid ?? const Uuid(),
        _clock = clock ?? DateTime.now;

  final LocalDatabase _db;
  final OutboxStore _outbox;
  final Uuid _uuid;
  final DateTime Function() _clock;

  @override
  Future<PaymentModel> recordPayment(PaymentDraft draft) async {
    final id = _uuid.v4();
    final now = _clock();
    final payment = PaymentModel(
      id: id,
      orderLocalId: draft.orderLocalId,
      orderRef: draft.orderRef,
      amount: draft.amount,
      method: draft.method,
      createdAt: now,
      tendered: draft.tendered,
      createdOffline: draft.createdOffline,
    );
    final entry = OutboxEntry(
      operationId: _uuid.v4(),
      entityType: 'payment',
      entityId: id,
      operationType: 'recordPayment',
      payload: {
        'id': id,
        'orderLocalId': draft.orderLocalId,
        'orderRef': draft.orderRef,
        'amount': draft.amount,
        'method': draft.method.name,
      },
      schemaVersion: AppVersion.localSchemaVersion,
      idempotencyKey: _uuid.v4(),
      createdAt: now,
    );

    await _db.transaction((txn) async {
      await LocalStores.payments.record(id).put(txn, payment.toRecord());
      await _outbox.append(txn, entry);
    });
    AppLogger.info('Payment $id queued (offline=${draft.createdOffline}).');
    return payment;
  }

  @override
  Future<List<PaymentModel>> listPayments() async {
    final snapshots = await LocalStores.payments.find(_db.db);
    final payments =
        snapshots.map((s) => PaymentModel.fromRecord(s.value)).toList();
    payments.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return payments;
  }

  /// Marks the payment an outbox entry refers to as synced.
  Future<void> applySynced(OutboxEntry entry) async {
    if (entry.entityType != 'payment') return;
    final record = LocalStores.payments.record(entry.entityId);
    final existing = await record.get(_db.db);
    if (existing == null) return;
    final payment = PaymentModel.fromRecord(existing);
    payment.syncStatus = SyncStatus.synced;
    await record.put(_db.db, payment.toRecord());
  }

  /// Writes demo payments so the accounting ledger is populated in demo mode.
  Future<void> seedPayments(List<PaymentModel> payments) async {
    if (payments.isEmpty) return;
    await _db.transaction((txn) async {
      for (final payment in payments) {
        await LocalStores.payments
            .record(payment.id)
            .put(txn, payment.toRecord());
      }
    });
    AppLogger.info('Seeded ${payments.length} demo payments.');
  }
}

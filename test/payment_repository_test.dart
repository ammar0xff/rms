import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/data/local/local_database.dart';
import 'package:rms/src/data/local/outbox/outbox_entry.dart';
import 'package:rms/src/data/local/outbox/outbox_status.dart';
import 'package:rms/src/data/local/outbox/outbox_store.dart';
import 'package:rms/src/data/repositories/local_payment_repository.dart';
import 'package:rms/src/domain/models/payment.dart';

int _seq = 0;

Future<LocalDatabase> _memoryDb() => LocalDatabase.memory('rms_pay_${_seq++}');

void main() {
  late LocalDatabase db;
  late LocalPaymentRepository repo;

  setUp(() async {
    db = await _memoryDb();
    repo = LocalPaymentRepository(
      db,
      clock: () => DateTime(2026, 10, 12, 12, 30),
    );
  });

  tearDown(() => db.close());

  test('records a pending cash payment and an outbox entry atomically',
      () async {
    final payment = await repo.recordPayment(const PaymentDraft(
      orderLocalId: 'o1',
      orderRef: 'O-1',
      amount: 42.5,
      method: PaymentMethod.cash,
      tendered: 50,
    ));

    expect(payment.syncStatus, SyncStatus.pendingSync);
    expect(payment.changeDue, 7.5);
    expect(payment.isRefund, isFalse);
    expect(payment.createdAt, DateTime(2026, 10, 12, 12, 30));

    final stored = (await repo.listPayments()).single;
    expect(stored.id, payment.id);
    expect(stored.orderRef, 'O-1');

    final entry = (await OutboxStore(db).all()).single;
    expect(entry.entityType, 'payment');
    expect(entry.operationType, 'recordPayment');
    expect(entry.entityId, payment.id);
    expect(entry.payload['method'], 'cash');
    expect(entry.schemaVersion, greaterThan(0));
  });

  test('card payments carry no change due', () async {
    final payment = await repo.recordPayment(const PaymentDraft(
      orderLocalId: 'o2',
      orderRef: 'O-2',
      amount: 10,
      method: PaymentMethod.card,
    ));
    expect(payment.changeDue, isNull);
  });

  test('change never goes negative', () async {
    final payment = await repo.recordPayment(const PaymentDraft(
      orderLocalId: 'o3',
      orderRef: 'O-3',
      amount: 20,
      method: PaymentMethod.cash,
      tendered: 5,
    ));
    expect(payment.changeDue, 0);
  });

  test('round-trips a payment through a record', () async {
    final payment = await repo.recordPayment(const PaymentDraft(
      orderLocalId: 'o4',
      orderRef: 'O-4',
      amount: 9.5,
      method: PaymentMethod.card,
      createdOffline: true,
    ));
    final restored = PaymentModel.fromRecord(payment.toRecord());
    expect(restored.id, payment.id);
    expect(restored.amount, 9.5);
    expect(restored.method, PaymentMethod.card);
    expect(restored.createdOffline, isTrue);
    expect(restored.createdAt, payment.createdAt);
  });

  test('applySynced marks the payment synced and ignores other entities',
      () async {
    final payment = await repo.recordPayment(const PaymentDraft(
      orderLocalId: 'o5',
      orderRef: 'O-5',
      amount: 5,
      method: PaymentMethod.cash,
    ));

    await repo.applySynced(OutboxEntry(
      operationId: 'op1',
      entityType: 'payment',
      entityId: payment.id,
      operationType: 'recordPayment',
      payload: const {'serverId': 'srv-1'},
      schemaVersion: 1,
      idempotencyKey: 'k1',
      createdAt: DateTime.utc(2026, 1, 1),
    ));
    expect((await repo.listPayments()).single.syncStatus, SyncStatus.synced);

    await repo.applySynced(OutboxEntry(
      operationId: 'op2',
      entityType: 'order',
      entityId: 'missing',
      operationType: 'createOrder',
      payload: const {},
      schemaVersion: 1,
      idempotencyKey: 'k2',
      createdAt: DateTime.utc(2026, 1, 1),
    ));
    expect(await repo.listPayments(), hasLength(1));
  });

  test('listPayments is ordered by creation time', () async {
    var minute = 0;
    final repo2 = LocalPaymentRepository(
      db,
      clock: () => DateTime(2026, 10, 12, 12, minute++),
    );
    for (var i = 0; i < 3; i++) {
      await repo2.recordPayment(PaymentDraft(
        orderLocalId: 'o$i',
        orderRef: 'O-$i',
        amount: (i + 1).toDouble(),
        method: PaymentMethod.cash,
      ));
    }
    final times = (await repo2.listPayments()).map((p) => p.createdAt).toList();
    expect(times, isNot(contains(null)));
    final sorted = [...times]..sort();
    expect(times, sorted);
  });
}

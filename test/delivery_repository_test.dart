import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/data/local/local_database.dart';
import 'package:rms/src/data/local/outbox/outbox_entry.dart';
import 'package:rms/src/data/local/outbox/outbox_status.dart';
import 'package:rms/src/data/local/outbox/outbox_store.dart';
import 'package:rms/src/data/repositories/delivery_repository.dart';
import 'package:rms/src/data/repositories/local_delivery_repository.dart';
import 'package:rms/src/domain/models/collection.dart';
import 'package:rms/src/domain/models/delivery.dart';
import 'package:rms/src/domain/models/payment.dart';

int _seq = 0;

Future<LocalDatabase> _memoryDb() => LocalDatabase.memory('rms_del_${_seq++}');

void main() {
  late LocalDatabase db;
  late LocalDeliveryRepository repo;

  setUp(() async {
    db = await _memoryDb();
    repo = LocalDeliveryRepository(
      db,
      clock: () => DateTime(2026, 10, 12, 13),
    );
  });

  tearDown(() => db.close());

  /// Creates a fully delivered job (assigned → onRoute → delivered).
  Future<DeliveryModel> delivered(String orderRef) async {
    final delivery = await repo.createDelivery(
      orderRef: orderRef,
      address: 'شارع الأرز',
      amount: 10,
    );
    await repo.assignDriver(delivery.id, 'مروان ر.');
    await repo.updateState(delivery.id, DeliveryState.onRoute);
    await repo.updateState(delivery.id, DeliveryState.delivered);
    return delivery;
  }

  test('starts empty', () async {
    expect(await repo.listDeliveries(), isEmpty);
    expect(await repo.listDrivers(), isEmpty);
    expect(await repo.listCollections(), isEmpty);
  });

  test('caches the courier roster', () async {
    await repo.cacheDrivers(const [
      DriverModel(id: 'd1', name: 'مروان ر.'),
      DriverModel(id: 'd2', name: 'سارة ك.', available: false),
    ]);
    final drivers = await repo.listDrivers();
    expect(drivers, hasLength(2));
    expect(drivers.firstWhere((d) => d.id == 'd2').available, isFalse);

    await repo.cacheDrivers(const [DriverModel(id: 'd3', name: 'ديڤ ب.')]);
    expect(await repo.listDrivers(), hasLength(1));
  });

  test('creates a waiting delivery with an outbox command', () async {
    final delivery = await repo.createDelivery(
      orderRef: 'O-1',
      address: 'شارع الأرز',
      amount: 30,
      createdOffline: true,
    );

    expect(delivery.state, DeliveryState.waiting);
    expect(delivery.isUnassigned, isTrue);
    expect(delivery.offline, isTrue);
    expect(delivery.settlementStatus, SettlementStatus.pending);
    expect(delivery.syncStatus, SyncStatus.pendingSync);

    expect(await repo.listDeliveries(), hasLength(1));
    final entry = (await OutboxStore(db).all()).single;
    expect(entry.entityType, 'delivery');
    expect(entry.operationType, 'createDelivery');
    expect(entry.payload['orderRef'], 'O-1');
  });

  test('assigning a driver marks the job assigned and queues a command',
      () async {
    final delivery = await repo.createDelivery(
      orderRef: 'O-2',
      address: 'شارع البتولا',
      amount: 20,
    );
    final outcome = await repo.assignDriver(delivery.id, 'مروان ر.');

    expect(outcome, AssignmentOutcome.assigned);
    final stored = (await repo.listDeliveries()).single;
    expect(stored.driver, 'مروان ر.');
    expect(stored.state, DeliveryState.assigned);
    expect(stored.syncStatus, SyncStatus.pendingSync);

    final types =
        (await OutboxStore(db).all()).map((e) => e.operationType).toList();
    expect(types, containsAll(['createDelivery', 'assignDriver']));
  });

  test('state transitions are persisted and queued', () async {
    final delivery = await delivered('O-3');

    final stored = (await repo.listDeliveries()).single;
    expect(stored.state, DeliveryState.delivered);
    expect(stored.state.isOpen, isFalse);
    expect(stored.settlementStatus, SettlementStatus.pending);

    final ops = (await OutboxStore(db).all())
        .where((e) => e.operationType == 'deliveryState')
        .length;
    expect(ops, 2);
    expect(delivery.id, stored.id);
  });

  test('reassignment from a stale base is recorded as a conflict', () async {
    final delivery = await repo.createDelivery(
      orderRef: 'O-4',
      address: 'شارع الصنوبر',
      amount: 12,
    );
    await repo.assignDriver(delivery.id, 'سارة ك.');

    final outcome = await repo.assignDriver(
      delivery.id,
      'مروان ر.',
      baseDriver: 'ديڤ ب.',
    );

    expect(outcome, AssignmentOutcome.conflict);
    final stored = (await repo.listDeliveries()).single;
    expect(stored.driver, 'سارة ك.'); // the newer assignment wins
    expect(stored.syncStatus, SyncStatus.conflict);

    final conflict = (await OutboxStore(db).all())
        .where((e) => e.syncStatus == OutboxStatus.conflict)
        .single;
    expect(conflict.operationType, 'reassignDeliveryConflict');
    expect(conflict.payload['currentDriver'], 'سارة ك.');
    expect(conflict.payload['attemptedDriver'], 'مروان ر.');
  });

  test('a matching base assigns normally', () async {
    final delivery = await repo.createDelivery(
      orderRef: 'O-5',
      address: 'شارع النخيل',
      amount: 12,
    );
    await repo.assignDriver(delivery.id, 'سارة ك.');
    final outcome = await repo.assignDriver(
      delivery.id,
      'مروان ر.',
      baseDriver: 'سارة ك.',
    );
    expect(outcome, AssignmentOutcome.assigned);
    expect((await repo.listDeliveries()).single.driver, 'مروان ر.');
  });

  test('a collection cannot be recorded before delivery', () async {
    final delivery = await repo.createDelivery(
      orderRef: 'O-6',
      address: '—',
      amount: 10,
    );
    expect(
      await repo.recordCollection(deliveryId: delivery.id, amount: 10),
      isNull,
    );
    expect(await repo.listCollections(), isEmpty);
  });

  test('a collection is recorded once and marks the job pending settlement',
      () async {
    final delivery = await delivered('O-7');
    final collection = await repo.recordCollection(
      deliveryId: delivery.id,
      amount: 12.5,
      createdOffline: true,
    );

    expect(collection, isNotNull);
    expect(collection!.settlementStatus, SettlementStatus.pending);
    expect(collection.createdOffline, isTrue);
    expect(collection.method, PaymentMethod.cash);

    final stored = (await repo.listDeliveries()).single;
    expect(stored.settlementStatus, SettlementStatus.pending);
    expect(stored.syncStatus, SyncStatus.pendingSync);

    // A second recording for the same job is a no-op — no duplicate money.
    expect(await repo.recordCollection(deliveryId: delivery.id, amount: 99), isNull);
    expect(await repo.listCollections(), hasLength(1));

    final entry = (await OutboxStore(db).all())
        .firstWhere((e) => e.operationType == 'recordCollection');
    expect(entry.entityType, 'collection');
    expect(entry.entityId, collection.id);
    expect(entry.payload['amount'], 12.5);
  });

  test('finalizeSettlement queues exactly one settle command', () async {
    final delivery = await delivered('O-8');
    await repo.recordCollection(deliveryId: delivery.id, amount: 10);

    await repo.finalizeSettlement(delivery.id);
    await repo.finalizeSettlement(delivery.id); // idempotent

    final settles = (await OutboxStore(db).all())
        .where((e) => e.operationType == 'settleDelivery')
        .toList();
    expect(settles, hasLength(1));
    expect(settles.single.entityId, delivery.id);
    expect(settles.single.payload['settlement'], 10.0);

    // Still awaiting server confirmation.
    expect(
      (await repo.listDeliveries()).single.settlementStatus,
      SettlementStatus.pending,
    );
  });

  test('a settlement acknowledgment settles the job and its collection',
      () async {
    final delivery = await delivered('O-9');
    await repo.recordCollection(deliveryId: delivery.id, amount: 10);

    await repo.applySynced(OutboxEntry(
      operationId: 'op-settle',
      entityType: 'delivery',
      entityId: delivery.id,
      operationType: 'settleDelivery',
      payload: const {},
      schemaVersion: 1,
      idempotencyKey: 'settle-1',
      createdAt: DateTime.utc(2026, 1, 1),
    ));

    expect(
      (await repo.listDeliveries()).single.settlementStatus,
      SettlementStatus.settled,
    );
    final collection = (await repo.listCollections()).single;
    expect(collection.settlementStatus, SettlementStatus.settled);
    expect(collection.syncStatus, SyncStatus.synced);
  });

  test('a collection acknowledgment marks the collection synced', () async {
    final delivery = await delivered('O-10');
    final collection = await repo.recordCollection(
      deliveryId: delivery.id,
      amount: 7,
    );

    await repo.applySynced(OutboxEntry(
      operationId: 'op-col',
      entityType: 'collection',
      entityId: collection!.id,
      operationType: 'recordCollection',
      payload: const {'serverId': 'srv-1'},
      schemaVersion: 1,
      idempotencyKey: 'col-1',
      createdAt: DateTime.utc(2026, 1, 1),
    ));

    expect((await repo.listCollections()).single.syncStatus, SyncStatus.synced);
  });

  test('a delivery round-trips through a record', () async {
    final delivery = await repo.createDelivery(
      orderRef: 'O-11',
      address: 'شارع النخيل',
      amount: 17.5,
    );
    final restored = DeliveryModel.fromRecord(delivery.toRecord());
    expect(restored.id, delivery.id);
    expect(restored.state, DeliveryState.waiting);
    expect(restored.amount, 17.5);
    expect(restored.driver, DeliveryModel.unassignedDriver);
    expect(restored.settlementStatus, SettlementStatus.pending);
    expect(restored.localRevision, 1);
  });

  test('a collection round-trips through a record', () async {
    final delivery = await delivered('O-12');
    final collection = await repo.recordCollection(
      deliveryId: delivery.id,
      amount: 17.5,
      method: PaymentMethod.card,
      createdOffline: true,
    );
    final restored = CollectionModel.fromRecord(collection!.toRecord());
    expect(restored.id, collection.id);
    expect(restored.deliveryId, delivery.id);
    expect(restored.amount, 17.5);
    expect(restored.method, PaymentMethod.card);
    expect(restored.createdOffline, isTrue);
    expect(restored.settlementStatus, SettlementStatus.pending);
  });
}

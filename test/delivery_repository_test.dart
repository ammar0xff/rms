import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/data/local/local_database.dart';
import 'package:rms/src/data/local/outbox/outbox_entry.dart';
import 'package:rms/src/data/local/outbox/outbox_status.dart';
import 'package:rms/src/data/local/outbox/outbox_store.dart';
import 'package:rms/src/data/repositories/local_delivery_repository.dart';
import 'package:rms/src/domain/models/delivery.dart';

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

  test('starts empty', () async {
    expect(await repo.listDeliveries(), isEmpty);
    expect(await repo.listDrivers(), isEmpty);
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
    await repo.assignDriver(delivery.id, 'مروان ر.');

    final stored = (await repo.listDeliveries()).single;
    expect(stored.driver, 'مروان ر.');
    expect(stored.state, DeliveryState.assigned);
    expect(stored.syncStatus, SyncStatus.pendingSync);

    final types =
        (await OutboxStore(db).all()).map((e) => e.operationType).toList();
    expect(types, containsAll(['createDelivery', 'assignDriver']));
  });

  test('state transitions are persisted and queued', () async {
    final delivery = await repo.createDelivery(
      orderRef: 'O-3',
      address: 'شارع الصنوبر',
      amount: 12,
    );
    await repo.assignDriver(delivery.id, 'سارة ك.');
    await repo.updateState(delivery.id, DeliveryState.onRoute);
    await repo.updateState(delivery.id, DeliveryState.collected);

    expect((await repo.listDeliveries()).single.state, DeliveryState.collected);
    final ops = (await OutboxStore(db).all())
        .map((e) => e.operationType)
        .where((t) => t == 'deliveryState')
        .length;
    expect(ops, 2);
  });

  test('applySynced marks the delivery synced and ignores unknown jobs',
      () async {
    final delivery = await repo.createDelivery(
      orderRef: 'O-4',
      address: '—',
      amount: 5,
    );
    await repo.applySynced(OutboxEntry(
      operationId: 'op',
      entityType: 'delivery',
      entityId: delivery.id,
      operationType: 'createDelivery',
      payload: const {'serverId': 'srv-9'},
      schemaVersion: 1,
      idempotencyKey: 'k',
      createdAt: DateTime.utc(2026, 1, 1),
    ));
    expect((await repo.listDeliveries()).single.syncStatus, SyncStatus.synced);

    await repo.applySynced(OutboxEntry(
      operationId: 'op2',
      entityType: 'delivery',
      entityId: 'missing',
      operationType: 'createDelivery',
      payload: const {},
      schemaVersion: 1,
      idempotencyKey: 'k2',
      createdAt: DateTime.utc(2026, 1, 1),
    ));
    expect(await repo.listDeliveries(), hasLength(1));
  });

  test('a delivery round-trips through a record', () async {
    final delivery = await repo.createDelivery(
      orderRef: 'O-5',
      address: 'شارع النخيل',
      amount: 17.5,
    );
    final restored = DeliveryModel.fromRecord(delivery.toRecord());
    expect(restored.id, delivery.id);
    expect(restored.state, DeliveryState.waiting);
    expect(restored.amount, 17.5);
    expect(restored.driver, DeliveryModel.unassignedDriver);
  });
}

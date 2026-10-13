import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/data/local/local_database.dart';
import 'package:rms/src/data/local/outbox/outbox_store.dart';
import 'package:rms/src/data/repositories/delivery_repository.dart';
import 'package:rms/src/data/repositories/local_delivery_repository.dart';
import 'package:rms/src/domain/models/delivery.dart';

int _seq = 0;

Future<LocalDatabase> _memoryDb() => LocalDatabase.memory('rms_auto_${_seq++}');

void main() {
  late LocalDatabase db;
  late LocalDeliveryRepository repo;

  setUp(() async {
    db = await _memoryDb();
    repo = LocalDeliveryRepository(db, clock: () => DateTime(2026, 10, 12, 13));
  });

  tearDown(() => db.close());

  const drivers = [
    DriverModel(id: 'd1', name: 'Ali'),
    DriverModel(id: 'd2', name: 'Basma'),
  ];

  Future<int> assignCommands() async {
    final entries = await OutboxStore(db).all();
    return entries.where((e) => e.operationType == 'assignDriver').length;
  }

  test('assigns every waiting job to the available couriers', () async {
    await repo.cacheDrivers(drivers);
    await repo.createDelivery(orderRef: 'O-1', address: 'a', amount: 10);
    await repo.createDelivery(orderRef: 'O-2', address: 'b', amount: 10);
    await repo.createDelivery(orderRef: 'O-3', address: 'c', amount: 10);

    final results = await repo.autoAssignWaiting();

    expect(results, hasLength(3));
    expect(
      results.every((r) => r.outcome == AssignmentOutcome.assigned),
      isTrue,
    );

    final stored = await repo.listDeliveries();
    expect(stored.every((d) => d.state == DeliveryState.assigned), isTrue);
    expect(stored.every((d) => !d.isUnassigned), isTrue);
    // Five jobs would be needed to unbalance two couriers; three splits 2/1.
    final counts = <String, int>{};
    for (final d in stored) {
      counts[d.driver] = (counts[d.driver] ?? 0) + 1;
    }
    expect(counts.values.toList()..sort(), [1, 2]);
    expect(await assignCommands(), 3);
  });

  test('does nothing when no courier is available', () async {
    await repo.cacheDrivers(
      const [DriverModel(id: 'd1', name: 'Ali', available: false)],
    );
    await repo.createDelivery(orderRef: 'O-1', address: 'a', amount: 10);

    final results = await repo.autoAssignWaiting();

    expect(results, isEmpty);
    expect((await repo.listDeliveries()).single.state, DeliveryState.waiting);
    expect(await assignCommands(), 0);
  });

  test('skips unavailable couriers', () async {
    await repo.cacheDrivers(const [
      DriverModel(id: 'd1', name: 'Ali'),
      DriverModel(id: 'd2', name: 'Basma', available: false),
    ]);
    await repo.createDelivery(orderRef: 'O-1', address: 'a', amount: 10);

    await repo.autoAssignWaiting();

    expect((await repo.listDeliveries()).single.driver, 'Ali');
  });

  test('is idempotent: a second run assigns nothing new', () async {
    await repo.cacheDrivers(drivers);
    await repo.createDelivery(orderRef: 'O-1', address: 'a', amount: 10);
    await repo.createDelivery(orderRef: 'O-2', address: 'b', amount: 10);

    final first = await repo.autoAssignWaiting();
    final second = await repo.autoAssignWaiting();

    expect(first, hasLength(2));
    expect(second, isEmpty);
    expect(await assignCommands(), 2);
  });

  test('never reassigns a job that is already dispatched', () async {
    await repo.cacheDrivers(drivers);
    final dispatched = await repo.createDelivery(
      orderRef: 'O-1',
      address: 'a',
      amount: 10,
    );
    await repo.assignDriver(dispatched.id, 'Basma');
    await repo.createDelivery(orderRef: 'O-2', address: 'b', amount: 10);

    final results = await repo.autoAssignWaiting();

    expect(results, hasLength(1));
    expect(results.single.deliveryId, isNot(dispatched.id));
    final stored = await repo.listDeliveries();
    expect(
      stored.firstWhere((d) => d.id == dispatched.id).driver,
      'Basma',
    );
    // One manual assignDriver plus the single auto-assigned job.
    expect(await assignCommands(), 2);
  });
}

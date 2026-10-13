import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/data/local/local_database.dart';
import 'package:rms/src/data/local/migrations/local_migration_registry.dart';
import 'package:rms/src/data/local/migrations/local_migration_runner.dart';
import 'package:rms/src/data/local/outbox/outbox_store.dart';
import 'package:rms/src/data/repositories/local_delivery_repository.dart';
import 'package:rms/src/domain/models/collection.dart';
import 'package:rms/src/domain/models/delivery.dart';

int _seq = 0;

Future<LocalDatabase> _memoryDb() => LocalDatabase.memory('rms_upgrade_${_seq++}');

void main() {
  late LocalDatabase db;

  setUp(() async {
    db = await _memoryDb();
  });

  tearDown(() => db.close());

  test('pending offline delivery work survives a schema upgrade', () async {
    final repo = LocalDeliveryRepository(
      db,
      outbox: OutboxStore(db),
      clock: () => DateTime(2026, 10, 13, 14),
    );

    // Capture a fully offline delivery: dispatch, delivery and collection all
    // queue commands that have not yet reached the backend.
    final delivery = await repo.createDelivery(
      orderRef: 'O-1',
      address: 'شارع التحرير',
      amount: 12,
      createdOffline: true,
    );
    await repo.assignDriver(delivery.id, 'مروان ر.');
    await repo.updateState(delivery.id, DeliveryState.onRoute);
    await repo.updateState(delivery.id, DeliveryState.delivered);
    await repo.recordCollection(deliveryId: delivery.id, amount: 12, createdOffline: true);

    final outbox = OutboxStore(db);
    final before = await outbox.all();
    expect(before, isNotEmpty);
    final beforeIds = before.map((e) => e.operationId).toList();

    // A new release runs its local migrations on first launch.
    final outcome = await LocalMigrationRunner(db, defaultLocalMigrations)
        .run(targetVersion: 4);
    expect(outcome.succeeded, isTrue);
    expect(outcome.toVersion, 4);

    // Every pending command is untouched and still drainable.
    final after = await outbox.all();
    expect(after.map((e) => e.operationId).toList(), beforeIds);
    expect(await outbox.pending(), hasLength(before.length));

    // Business state is intact and consistent.
    final deliveries = await repo.listDeliveries();
    expect(deliveries, hasLength(1));
    expect(deliveries.single.state, DeliveryState.delivered);
    expect(deliveries.single.settlementStatus, SettlementStatus.pending);
    final collections = await repo.listCollections();
    expect(collections, hasLength(1));
    expect(collections.single.settlementStatus, SettlementStatus.pending);
  });
}

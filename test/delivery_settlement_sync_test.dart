import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sembast/sembast_io.dart';

import 'package:rms/src/data/local/local_database.dart';
import 'package:rms/src/data/local/outbox/outbox_status.dart';
import 'package:rms/src/data/local/outbox/outbox_store.dart';
import 'package:rms/src/data/repositories/local_delivery_repository.dart';
import 'package:rms/src/data/sync/in_memory_sync_transport.dart';
import 'package:rms/src/data/sync/retry_policy.dart';
import 'package:rms/src/data/sync/sync_coordinator.dart';
import 'package:rms/src/data/sync/sync_engine.dart';
import 'package:rms/src/domain/models/collection.dart';
import 'package:rms/src/domain/models/delivery.dart';

Future<LocalDatabase> _openFile(String dbPath) async =>
    LocalDatabase.fromDatabase(await databaseFactoryIo.openDatabase(dbPath));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late String dbPath;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('rms_settle_test');
    dbPath = p.join(tmp.path, 'rms_local.db');
  });

  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  test(
      'offline delivery collection survives restart and settles once confirmed',
      () async {
    // --- Offline: dispatch, deliver and collect, all without a backend. ---
    final db1 = await _openFile(dbPath);
    final repo1 = LocalDeliveryRepository(db1);
    final delivery = await repo1.createDelivery(
      orderRef: 'ORD-7001',
      address: '42 شارع الأرز',
      amount: 40,
      createdOffline: true,
    );
    await repo1.assignDriver(delivery.id, 'مروان ر.');
    await repo1.updateState(delivery.id, DeliveryState.onRoute);
    await repo1.updateState(delivery.id, DeliveryState.delivered);
    final collection = await repo1.recordCollection(
      deliveryId: delivery.id,
      amount: 40,
      createdOffline: true,
    );
    expect(collection, isNotNull);
    // create + assign + 2 states + collection.
    expect(await OutboxStore(db1).pending(), hasLength(5));
    await db1.close();

    // --- Restart: the offline activity is fully traceable. ---
    final db2 = await _openFile(dbPath);
    final repo2 = LocalDeliveryRepository(db2);
    final restoredDelivery = (await repo2.listDeliveries()).single;
    expect(restoredDelivery.id, delivery.id);
    expect(restoredDelivery.state, DeliveryState.delivered);
    expect(restoredDelivery.settlementStatus, SettlementStatus.pending);
    final restoredCollection = (await repo2.listCollections()).single;
    expect(restoredCollection.settlementStatus, SettlementStatus.pending);
    expect(restoredCollection.createdOffline, isTrue);

    // Recording again never duplicates the collection.
    expect(
      await repo2.recordCollection(deliveryId: delivery.id, amount: 40),
      isNull,
    );
    expect(await repo2.listCollections(), hasLength(1));

    // --- Reconnect: the backlog drains exactly once. ---
    final transport = InMemorySyncTransport()..online = false;
    final coordinator = SyncCoordinator(
      engine: SyncEngine(
        transport: transport,
        outbox: OutboxStore(db2),
        onApplied: repo2.applySynced,
        retryPolicy: RetryPolicy(baseDelay: Duration.zero),
      ),
    );
    expect(await coordinator.requestSync(), 0);
    transport.online = true;
    expect(await coordinator.requestSync(), 5);
    expect((await repo2.listDeliveries()).single.syncStatus, SyncStatus.synced);

    // Money is recorded on the server, but *not yet settled*.
    final syncedCollection = (await repo2.listCollections()).single;
    expect(syncedCollection.syncStatus, SyncStatus.synced);
    expect(syncedCollection.settlementStatus, SettlementStatus.pending);

    // --- Online settlement finalization. ---
    await repo2.finalizeSettlement(delivery.id);
    expect(await coordinator.requestSync(), 1);
    expect(
      (await repo2.listDeliveries()).single.settlementStatus,
      SettlementStatus.settled,
    );
    expect(
      (await repo2.listCollections()).single.settlementStatus,
      SettlementStatus.settled,
    );

    // Replaying the settlement never duplicates it server-side.
    final settle = (await OutboxStore(db2).all())
        .firstWhere((e) => e.operationType == 'settleDelivery');
    final applied = transport.appliedCount;
    await OutboxStore(db2).save(settle.copyWith(
      syncStatus: OutboxStatus.pending,
      attemptCount: 0,
    ));
    expect(await coordinator.requestSync(), 1);
    expect(transport.appliedCount, applied);

    // A second finalize is a no-op: already settled, no new command queued.
    await repo2.finalizeSettlement(delivery.id);
    final settleCount = (await OutboxStore(db2).all())
        .where((e) => e.operationType == 'settleDelivery')
        .length;
    expect(settleCount, 1);

    await db2.close();
  });
}

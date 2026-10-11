import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sembast/sembast_io.dart';

import 'package:rms/src/data/local/local_database.dart';
import 'package:rms/src/data/local/outbox/outbox_status.dart';
import 'package:rms/src/data/local/outbox/outbox_store.dart';
import 'package:rms/src/data/repositories/local_order_repository.dart';
import 'package:rms/src/data/sync/in_memory_sync_transport.dart';
import 'package:rms/src/data/sync/retry_policy.dart';
import 'package:rms/src/data/sync/sync_coordinator.dart';
import 'package:rms/src/data/sync/sync_engine.dart';
import 'package:rms/src/domain/models/order.dart';
import 'package:rms/src/domain/models/order_draft.dart';

const List<OrderItem> _lineItems = [
  OrderItem(productId: 'p1', name: 'برجر', unitPrice: 45, quantity: 2),
  OrderItem(productId: 'p2', name: 'عصير', unitPrice: 15, quantity: 1),
];

Future<LocalDatabase> _openFile(String dbPath) async =>
    LocalDatabase.fromDatabase(await databaseFactoryIo.openDatabase(dbPath));

SyncCoordinator _coordinator(LocalDatabase db, LocalOrderRepository repo,
        InMemorySyncTransport transport) =>
    SyncCoordinator(
      engine: SyncEngine(
        transport: transport,
        outbox: OutboxStore(db),
        onApplied: repo.applySynced,
        retryPolicy: RetryPolicy(baseDelay: Duration.zero),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late String dbPath;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('rms_test');
    dbPath = p.join(tmp.path, 'rms_local.db');
  });

  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  test('offline order survives a restart with a matching outbox entry', () async {
    final db1 = await _openFile(dbPath);
    final repo1 = LocalOrderRepository(db1);
    final created = await repo1.createOrder(
      const OrderDraft(items: _lineItems, createdOffline: true),
    );
    expect((await repo1.listOrders()).single.syncStatus, SyncStatus.pendingSync);
    expect(await OutboxStore(db1).pending(), hasLength(1));
    await db1.close();

    final db2 = await _openFile(dbPath);
    final repo2 = LocalOrderRepository(db2);
    final orders = await repo2.listOrders();
    expect(orders, hasLength(1));
    expect(orders.single.localId, created.localId);
    expect(orders.single.syncStatus, SyncStatus.pendingSync);
    expect(await OutboxStore(db2).pending(), hasLength(1));
    await db2.close();
  });

  test('syncs on reconnect exactly once and dedupes on replay', () async {
    final db = await _openFile(dbPath);
    final repo = LocalOrderRepository(db);
    final transport = InMemorySyncTransport()..online = false;
    final coordinator = _coordinator(db, repo, transport);

    await repo.createOrder(const OrderDraft(items: _lineItems));

    expect(await coordinator.requestSync(), 0);
    expect(transport.appliedCount, 0);

    transport.online = true;
    expect(await coordinator.requestSync(), 1);
    expect(transport.appliedCount, 1);
    expect((await repo.listOrders()).single.syncStatus, SyncStatus.synced);
    final key = transport.accepted.single.idempotencyKey;

    final entry = (await OutboxStore(db).all()).single;
    await OutboxStore(db).save(entry.copyWith(syncStatus: OutboxStatus.pending));
    expect(await coordinator.requestSync(), 1);
    expect(transport.appliedCount, 1);
    expect(transport.hasApplied(key), isTrue);

    await db.close();
  });

  test('a transient failure is retried and then applied', () async {
    final db = await _openFile(dbPath);
    final repo = LocalOrderRepository(db);
    final transport = InMemorySyncTransport()..failNextPush = true;
    final coordinator = _coordinator(db, repo, transport);

    await repo.createOrder(const OrderDraft(items: _lineItems));

    expect(await coordinator.requestSync(), 0);
    final failed = (await OutboxStore(db).all()).single;
    expect(failed.syncStatus, OutboxStatus.retryableFailure);
    expect(failed.attemptCount, 1);
    expect(failed.lastError, isNotNull);
    expect((await repo.listOrders()).single.syncStatus, SyncStatus.pendingSync);

    expect(await coordinator.requestSync(), 1);
    expect((await OutboxStore(db).all()).single.syncStatus, OutboxStatus.synced);
    expect((await repo.listOrders()).single.syncStatus, SyncStatus.synced);

    await db.close();
  });

  test('a failing transaction leaves no partial records', () async {
    final db = await _openFile(dbPath);
    final store = stringMapStoreFactory.store('scratch');

    await expectLater(
      db.transaction((txn) async {
        await store.record('a').put(txn, {'value': 1});
        throw StateError('boom');
      }),
      throwsA(isA<StateError>()),
    );
    expect(await store.find(db.db), isEmpty);
    await db.close();
  });
}

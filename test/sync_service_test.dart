import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/data/local/local_database.dart';
import 'package:rms/src/data/local/outbox/outbox_entry.dart';
import 'package:rms/src/data/local/outbox/outbox_status.dart';
import 'package:rms/src/data/local/outbox/outbox_store.dart';
import 'package:rms/src/data/sync/connectivity_monitor.dart';
import 'package:rms/src/data/sync/in_memory_sync_transport.dart';
import 'package:rms/src/data/sync/sync_coordinator.dart';
import 'package:rms/src/data/sync/sync_engine.dart';
import 'package:rms/src/data/sync/sync_service.dart';

int _seq = 0;

Future<LocalDatabase> _memoryDb() =>
    LocalDatabase.memory('rms_service_${_seq++}');

OutboxEntry _entry(String key) => OutboxEntry(
      operationId: 'op-$key',
      entityType: 'order',
      entityId: 'e-$key',
      operationType: 'createOrder',
      payload: const {'total': 1},
      schemaVersion: 1,
      idempotencyKey: key,
      createdAt: DateTime.utc(2026, 1, 1),
    );

Future<void> _seed(LocalDatabase db, OutboxStore store, String key) =>
    db.transaction((txn) => store.append(txn, _entry(key)));

SyncService _service(
  OutboxStore store,
  InMemorySyncTransport transport,
  ConnectivityMonitor monitor,
) =>
    SyncService(
      coordinator: SyncCoordinator(
        engine: SyncEngine(transport: transport, outbox: store),
      ),
      connectivity: monitor,
    );

/// Lets queued microtasks run until [condition] holds (or gives up).
Future<void> _until(bool Function() condition) async {
  for (var i = 0; i < 1000 && !condition(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('SyncService', () {
    test('syncs queued entries when started online', () async {
      final db = await _memoryDb();
      final store = OutboxStore(db);
      await _seed(db, store, 'k1');
      final transport = InMemorySyncTransport();
      final service = _service(
        store,
        transport,
        ConnectivityMonitor(
          changes: const Stream<List<ConnectivityResult>>.empty(),
          check: () async => [ConnectivityResult.wifi],
        ),
      );

      await service.start();
      await _until(() => transport.appliedCount == 1);
      await _until(() async {
        final all = await store.all();
        return all.isNotEmpty && all.single.syncStatus == OutboxStatus.synced;
      }());

      expect(service.isOnline, isTrue);
      expect(transport.appliedCount, 1);
      expect((await store.all()).single.syncStatus, OutboxStatus.synced);

      await service.dispose();
      await db.close();
    });

    test('waits offline, then syncs once connectivity returns', () async {
      final controller = StreamController<List<ConnectivityResult>>();
      addTearDown(controller.close);
      final db = await _memoryDb();
      final store = OutboxStore(db);
      await _seed(db, store, 'k1');
      final transport = InMemorySyncTransport();
      final service = _service(
        store,
        transport,
        ConnectivityMonitor(
          changes: controller.stream,
          check: () async => [ConnectivityResult.none],
        ),
      );

      await service.start();
      await _until(() => false);
      expect(service.isOnline, isFalse);
      expect(transport.appliedCount, 0);

      controller.add([ConnectivityResult.wifi]);
      await _until(() => transport.appliedCount == 1);
      await _until(() async {
        final all = await store.all();
        return all.isNotEmpty && all.single.syncStatus == OutboxStatus.synced;
      }());

      expect(service.isOnline, isTrue);
      expect((await store.all()).single.syncStatus, OutboxStatus.synced);

      await service.dispose();
      await db.close();
    });

    test('stops reacting to connectivity after dispose', () async {
      final controller = StreamController<List<ConnectivityResult>>();
      addTearDown(controller.close);
      final db = await _memoryDb();
      final store = OutboxStore(db);
      await _seed(db, store, 'k1');
      final transport = InMemorySyncTransport();
      final service = _service(
        store,
        transport,
        ConnectivityMonitor(
          changes: controller.stream,
          check: () async => [ConnectivityResult.none],
        ),
      );

      await service.start();
      await service.dispose();

      controller.add([ConnectivityResult.wifi]);
      await _until(() => false);

      expect(service.isOnline, isFalse);
      expect(transport.appliedCount, 0);

      await db.close();
    });
  });
}

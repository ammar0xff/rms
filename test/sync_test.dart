import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/data/local/local_database.dart';
import 'package:rms/src/data/local/outbox/outbox_entry.dart';
import 'package:rms/src/data/local/outbox/outbox_status.dart';
import 'package:rms/src/data/local/outbox/outbox_store.dart';
import 'package:rms/src/data/sync/in_memory_sync_transport.dart';
import 'package:rms/src/data/sync/retry_policy.dart';
import 'package:rms/src/data/sync/sync_coordinator.dart';
import 'package:rms/src/data/sync/sync_engine.dart';

int _seq = 0;

Future<LocalDatabase> _memoryDb() =>
    LocalDatabase.memory('rms_sync_${_seq++}');

OutboxEntry _entry({String key = 'k1'}) => OutboxEntry(
      operationId: 'op-$key',
      entityType: 'order',
      entityId: 'e-$key',
      operationType: 'createOrder',
      payload: const {'total': 1},
      schemaVersion: 1,
      idempotencyKey: key,
      createdAt: DateTime.utc(2026, 1, 1),
    );

Future<void> _seed(LocalDatabase db, OutboxStore store, {String key = 'k1'}) =>
    db.transaction((txn) => store.append(txn, _entry(key: key)));

class _BlockingTransport implements SyncTransport {
  final Completer<void> _gate = Completer<void>();
  int calls = 0;

  @override
  Future<Map<String, dynamic>> push(OutboxEntry entry) async {
    calls++;
    await _gate.future;
    return const {};
  }

  void release() => _gate.complete();
}

void main() {
  group('InMemorySyncTransport', () {
    test('applies each idempotency key at most once', () async {
      final transport = InMemorySyncTransport();
      await transport.push(_entry(key: 'dup'));
      await transport.push(_entry(key: 'dup'));
      expect(transport.appliedCount, 1);
      expect(transport.hasApplied('dup'), isTrue);
      expect(transport.hasApplied('other'), isFalse);
    });

    test('fails while offline and on a scripted transient error', () async {
      final transport = InMemorySyncTransport()..online = false;
      await expectLater(
        transport.push(_entry()),
        throwsA(isA<StateError>()),
      );

      transport
        ..online = true
        ..failNextPush = true;
      await expectLater(
        transport.push(_entry()),
        throwsA(isA<StateError>()),
      );
      await transport.push(_entry());
      expect(transport.appliedCount, 1);
    });
  });

  group('SyncEngine.drain', () {
    late LocalDatabase db;
    late OutboxStore store;

    setUp(() async {
      db = await _memoryDb();
      store = OutboxStore(db);
    });

    tearDown(() => db.close());

    test('applies pending entries and marks them synced', () async {
      await _seed(db, store);
      final transport = InMemorySyncTransport();
      final applied = <OutboxEntry>[];
      final engine = SyncEngine(
        transport: transport,
        outbox: store,
        onApplied: (entry) async => applied.add(entry),
      );

      expect(await engine.drain(), 1);
      expect(transport.appliedCount, 1);
      expect((await store.all()).single.syncStatus, OutboxStatus.synced);
      expect(applied.single.idempotencyKey, 'k1');
    });

    test('works without an onApplied callback', () async {
      await _seed(db, store);
      final engine =
          SyncEngine(transport: InMemorySyncTransport(), outbox: store);
      expect(await engine.drain(), 1);
    });

    test('records a retryable failure when the transport is offline', () async {
      await _seed(db, store);
      final engine = SyncEngine(
        transport: InMemorySyncTransport()..online = false,
        outbox: store,
      );

      expect(await engine.drain(), 0);
      final entry = (await store.all()).single;
      expect(entry.syncStatus, OutboxStatus.retryableFailure);
      expect(entry.attemptCount, 1);
      expect(entry.lastError, isNotNull);
    });

    test('parks the entry for a human once the attempt budget is exhausted',
        () async {
      await _seed(db, store);
      final engine = SyncEngine(
        transport: InMemorySyncTransport()..online = false,
        outbox: store,
        retryPolicy: RetryPolicy(maxAttempts: 1),
      );

      expect(await engine.drain(), 0);
      expect((await store.all()).single.syncStatus,
          OutboxStatus.retryableFailure);
      // Exhaustion is detected at the start of a pass: this drain parks it
      // instead of skipping it silently forever.
      expect(await engine.drain(), 0);
      expect((await store.all()).single.syncStatus,
          OutboxStatus.requiresUserAction);
      // Parked entries leave the drain queue: no further attempts are burned.
      expect(await engine.drain(), 0);
      expect((await store.all()).single.attemptCount, 1);
    });

    test('backs off between attempts instead of retrying every pass',
        () async {
      await _seed(db, store);
      final engine = SyncEngine(
        transport: InMemorySyncTransport()..online = false,
        outbox: store,
        retryPolicy: RetryPolicy(
          baseDelay: const Duration(milliseconds: 60),
          maxAttempts: 8,
        ),
      );

      expect(await engine.drain(), 0);
      expect((await store.all()).single.attemptCount, 1);
      // Backoff has not elapsed: skipped, not attempted.
      expect(await engine.drain(), 0);
      expect((await store.all()).single.attemptCount, 1);

      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(await engine.drain(), 0);
      expect((await store.all()).single.attemptCount, 2);
    });

    test('stops retrying once the attempt budget is exhausted', () async {
      await _seed(db, store);
      final engine = SyncEngine(
        transport: InMemorySyncTransport()..online = false,
        outbox: store,
        retryPolicy: RetryPolicy(maxAttempts: 1),
      );

      expect(await engine.drain(), 0);
      expect((await store.all()).single.attemptCount, 1);
      expect(await engine.drain(), 0);
      expect((await store.all()).single.attemptCount, 1);
    });

    test('parks the entry when the local fold-back fails after a good push',
        () async {
      await _seed(db, store);
      final transport = InMemorySyncTransport();
      final engine = SyncEngine(
        transport: transport,
        outbox: store,
        onApplied: (_) async => throw StateError('disk blew up'),
      );

      // The server holds the entry; flipping it back to retryable would
      // re-push it and burn a second canonical order number.
      expect(await engine.drain(), 0);
      final entry = (await store.all()).single;
      expect(entry.syncStatus, OutboxStatus.requiresUserAction);
      expect(transport.appliedCount, 1);
      expect(await engine.drain(), 0);
      expect(transport.appliedCount, 1);
    });

    test('does not re-process already synced entries', () async {
      await _seed(db, store);
      await store.markSynced('op-k1');
      final transport = InMemorySyncTransport();
      final engine = SyncEngine(transport: transport, outbox: store);

      expect(await engine.drain(), 0);
      expect(transport.appliedCount, 0);
    });
  });

  group('RetryPolicy', () {
    test('shouldRetry respects the attempt budget', () {
      final policy = RetryPolicy(maxAttempts: 3);
      expect(policy.shouldRetry(0), isTrue);
      expect(policy.shouldRetry(2), isTrue);
      expect(policy.shouldRetry(3), isFalse);
    });

    test('nextDelay stays within [baseDelay, maxDelay]', () {
      final policy = RetryPolicy(
        baseDelay: const Duration(seconds: 2),
        maxDelay: const Duration(seconds: 30),
      );
      for (var attempt = 0; attempt < 12; attempt++) {
        final delay = policy.nextDelay(attempt);
        expect(delay, greaterThanOrEqualTo(policy.baseDelay));
        expect(delay, lessThanOrEqualTo(policy.maxDelay));
      }
    });
  });

  group('SyncCoordinator', () {
    test('runs a pass and reports how many entries were applied', () async {
      final db = await _memoryDb();
      final store = OutboxStore(db);
      await _seed(db, store);
      final coordinator = SyncCoordinator(
        engine: SyncEngine(transport: InMemorySyncTransport(), outbox: store),
      );

      expect(await coordinator.requestSync(), 1);
      expect(coordinator.isSyncing, isFalse);
      await db.close();
    });

    test('ignores concurrent requests while a pass is in flight', () async {
      final db = await _memoryDb();
      final store = OutboxStore(db);
      await _seed(db, store);
      final transport = _BlockingTransport();
      final coordinator = SyncCoordinator(
        engine: SyncEngine(transport: transport, outbox: store),
      );

      final first = coordinator.requestSync();
      for (var i = 0; i < 100 && transport.calls == 0; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(coordinator.isSyncing, isTrue);
      expect(await coordinator.requestSync(), 0);

      transport.release();
      expect(await first, 1);
      expect(transport.calls, 1);
      expect(coordinator.isSyncing, isFalse);
      await db.close();
    });
  });
}

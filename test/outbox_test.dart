import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/data/local/local_database.dart';
import 'package:rms/src/data/local/outbox/outbox_entry.dart';
import 'package:rms/src/data/local/outbox/outbox_status.dart';
import 'package:rms/src/data/local/outbox/outbox_store.dart';

int _seq = 0;

OutboxEntry _entry({String key = 'k1', DateTime? createdAt}) => OutboxEntry(
      operationId: 'op-$key',
      entityType: 'order',
      entityId: 'e1',
      operationType: 'createOrder',
      payload: const {'total': 10},
      schemaVersion: 1,
      idempotencyKey: key,
      createdAt: createdAt ?? DateTime.utc(2026, 1, 1),
    );

void main() {
  group('OutboxEntry', () {
    test('round-trips through a record', () {
      final entry = _entry(createdAt: DateTime.utc(2026, 5, 4, 3, 2, 1));
      final restored = OutboxEntry.fromRecord(entry.toRecord());
      expect(restored.operationId, entry.operationId);
      expect(restored.entityType, 'order');
      expect(restored.entityId, 'e1');
      expect(restored.operationType, 'createOrder');
      expect(restored.payload['total'], 10);
      expect(restored.schemaVersion, 1);
      expect(restored.idempotencyKey, 'k1');
      expect(restored.createdAt, entry.createdAt);
      expect(restored.syncStatus, OutboxStatus.pending);
      expect(restored.dependencyIds, isEmpty);
      expect(restored.attemptCount, 0);
      expect(restored.lastAttemptAt, isNull);
      expect(restored.lastError, isNull);
    });

    test('copyWith updates fields and can clear the last error', () {
      final failed = _entry().copyWith(
        syncStatus: OutboxStatus.retryableFailure,
        attemptCount: 3,
        lastError: 'boom',
      );
      expect(failed.syncStatus, OutboxStatus.retryableFailure);
      expect(failed.attemptCount, 3);
      expect(failed.lastError, 'boom');

      final cleared = failed.copyWith(
        syncStatus: OutboxStatus.synced,
        clearLastError: true,
      );
      expect(cleared.syncStatus, OutboxStatus.synced);
      expect(cleared.attemptCount, 3);
      expect(cleared.lastError, isNull);
    });
  });

  group('OutboxStore', () {
    late LocalDatabase db;
    late OutboxStore store;

    setUp(() async {
      db = await LocalDatabase.memory('rms_outbox_${_seq++}');
      store = OutboxStore(db);
    });

    tearDown(() => db.close());

    test('appends inside a transaction and lists in creation order', () async {
      await db.transaction((txn) => store
          .append(txn, _entry(key: 'b', createdAt: DateTime.utc(2026, 2, 1))));
      await db.transaction((txn) => store
          .append(txn, _entry(key: 'a', createdAt: DateTime.utc(2026, 1, 1))));

      final all = await store.all();
      expect(all.map((e) => e.idempotencyKey).toList(), ['a', 'b']);
      expect(await store.pending(), hasLength(2));
    });

    test('pending includes retryable but excludes synced entries', () async {
      await db.transaction((txn) async {
        await store.append(txn, _entry(key: 'p'));
        await store.append(txn, _entry(key: 'r'));
        await store.append(txn, _entry(key: 's'));
      });
      await store.markRetryable('op-r', 'transient');
      await store.markSynced('op-s');

      final keys = (await store.pending()).map((e) => e.idempotencyKey);
      expect(keys, containsAll(['p', 'r']));
      expect(keys, isNot(contains('s')));
    });

    test('markRetryable increments attempts and records the error', () async {
      await db.transaction((txn) => store.append(txn, _entry()));
      await store.markRetryable('op-k1', 'first');
      await store.markRetryable('op-k1', 'second');

      final entry = (await store.all()).single;
      expect(entry.attemptCount, 2);
      expect(entry.lastError, 'second');
      expect(entry.lastAttemptAt, isNotNull);
      expect(entry.syncStatus, OutboxStatus.retryableFailure);
    });

    test('markSynced clears prior failures', () async {
      await db.transaction((txn) => store.append(txn, _entry()));
      await store.markRetryable('op-k1', 'err');
      await store.markInProgress('op-k1');
      await store.markSynced('op-k1');

      final entry = (await store.all()).single;
      expect(entry.syncStatus, OutboxStatus.synced);
      expect(entry.lastError, isNull);
      expect(entry.lastAttemptAt, isNotNull);
    });

    test('byOperationId returns null for unknown ids', () async {
      await db.transaction((txn) => store.append(txn, _entry()));
      expect(await store.byOperationId('op-k1'), isNotNull);
      expect(await store.byOperationId('nope'), isNull);
    });

    test('marking a missing entry is a no-op', () async {
      await store.markSynced('missing');
      expect(await store.all(), isEmpty);
    });
  });
}

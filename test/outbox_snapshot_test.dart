import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/data/local/outbox/outbox_access.dart';
import 'package:rms/src/data/local/outbox/outbox_entry.dart';
import 'package:rms/src/data/local/outbox/outbox_snapshot.dart';
import 'package:rms/src/data/local/outbox/outbox_status.dart';

/// Serves a fixed set of entries so the mapping can be checked without a store.
class _FakeOutbox implements OutboxAccess {
  _FakeOutbox(this.entries);

  final List<OutboxEntry> entries;

  @override
  Future<List<OutboxEntry>> all() async => entries;

  @override
  Future<void> save(OutboxEntry entry) async {}
}

int _seq = 0;

OutboxEntry _entry(OutboxStatus status) => OutboxEntry(
      operationId: 'op-${_seq++}',
      entityType: 'order',
      entityId: 'O-$_seq',
      operationType: 'upsert',
      payload: const {},
      schemaVersion: 1,
      idempotencyKey: 'idem-$_seq',
      createdAt: DateTime(2026, 10, 13),
      syncStatus: status,
    );

void main() {
  group('loadLocalWorkSnapshot', () {
    test('a null store reports no work but keeps the connectivity flag',
        () async {
      final online = await loadLocalWorkSnapshot(null, online: true);
      expect(online.unsynced, 0);
      expect(online.stuck, 0);
      expect(online.synced, 0);
      expect(online.online, isTrue);

      final offline = await loadLocalWorkSnapshot(null, online: false);
      expect(offline.online, isFalse);
    });

    test('an empty outbox reports no work', () async {
      final work = await loadLocalWorkSnapshot(
        _FakeOutbox(const []),
        online: true,
      );

      expect(work.unsynced, 0);
      expect(work.stuck, 0);
      expect(work.hasUnsynced, isFalse);
      expect(work.hasStuck, isFalse);
    });

    test('each status lands in exactly the right counter', () async {
      final work = await loadLocalWorkSnapshot(
        _FakeOutbox([
          _entry(OutboxStatus.pending),
          _entry(OutboxStatus.inProgress),
          _entry(OutboxStatus.retryableFailure),
          _entry(OutboxStatus.conflict),
          _entry(OutboxStatus.requiresUserAction),
          _entry(OutboxStatus.permanentlyRejected),
          _entry(OutboxStatus.synced),
        ]),
        online: true,
      );

      expect(work.pending, 1);
      expect(work.inProgress, 1);
      expect(work.retryableFailure, 1);
      expect(work.conflict, 1);
      expect(work.requiresUserAction, 1);
      expect(work.permanentlyRejected, 1);
      expect(work.synced, 1);
    });

    // AC-35: work a sync can still deliver is never counted as stuck, and
    // work it can never deliver is never counted as unsynced. Conflating the
    // two would either withhold an install forever or permit one that drops
    // records.
    test('unsynced counts only what a sync can still deliver', () async {
      final work = await loadLocalWorkSnapshot(
        _FakeOutbox([
          _entry(OutboxStatus.pending),
          _entry(OutboxStatus.inProgress),
          _entry(OutboxStatus.retryableFailure),
          _entry(OutboxStatus.conflict),
          _entry(OutboxStatus.requiresUserAction),
          _entry(OutboxStatus.permanentlyRejected),
          _entry(OutboxStatus.synced),
        ]),
        online: true,
      );

      expect(work.unsynced, 3);
      expect(work.hasUnsynced, isTrue);
    });

    test('stuck counts only what a sync can never resolve', () async {
      final work = await loadLocalWorkSnapshot(
        _FakeOutbox([
          _entry(OutboxStatus.pending),
          _entry(OutboxStatus.inProgress),
          _entry(OutboxStatus.retryableFailure),
          _entry(OutboxStatus.conflict),
          _entry(OutboxStatus.requiresUserAction),
          _entry(OutboxStatus.permanentlyRejected),
          _entry(OutboxStatus.synced),
        ]),
        online: true,
      );

      expect(work.stuck, 3);
      expect(work.hasStuck, isTrue);
    });

    test('synced entries are counted as done, never as outstanding', () async {
      final work = await loadLocalWorkSnapshot(
        _FakeOutbox([
          for (var i = 0; i < 5; i++) _entry(OutboxStatus.synced),
        ]),
        online: true,
      );

      expect(work.synced, 5);
      expect(work.unsynced, 0);
      expect(work.stuck, 0);
      expect(work.hasUnsynced, isFalse);
      expect(work.hasStuck, isFalse);
    });

    test('every entry is accounted for exactly once', () async {
      final entries = <OutboxEntry>[
        for (var i = 0; i < 4; i++) _entry(OutboxStatus.pending),
        for (var i = 0; i < 3; i++) _entry(OutboxStatus.inProgress),
        for (var i = 0; i < 2; i++) _entry(OutboxStatus.conflict),
        for (var i = 0; i < 5; i++) _entry(OutboxStatus.synced),
      ];

      final work = await loadLocalWorkSnapshot(
        _FakeOutbox(entries),
        online: true,
      );

      final counted = work.pending +
          work.inProgress +
          work.retryableFailure +
          work.conflict +
          work.requiresUserAction +
          work.permanentlyRejected +
          work.synced;
      expect(counted, entries.length);
    });

    test('the connectivity flag is carried through unchanged', () async {
      final entries = [_entry(OutboxStatus.pending)];

      expect(
        (await loadLocalWorkSnapshot(_FakeOutbox(entries), online: true))
            .online,
        isTrue,
      );
      expect(
        (await loadLocalWorkSnapshot(_FakeOutbox(entries), online: false))
            .online,
        isFalse,
      );
    });

    test('a rejected record alone is stuck work, not unsynced work',
        () async {
      // The backend refused this order permanently. It will never sync, so it
      // is the case an operator has to acknowledge before an install.
      final work = await loadLocalWorkSnapshot(
        _FakeOutbox([_entry(OutboxStatus.permanentlyRejected)]),
        online: true,
      );

      expect(work.unsynced, 0);
      expect(work.stuck, 1);
      expect(work.hasUnsynced, isFalse);
      expect(work.hasStuck, isTrue);
    });

    test('an in-flight entry is outstanding after a crash', () async {
      // A push claimed the record but never acknowledged it, so it is still
      // owed to the backend and must withhold an install.
      final work = await loadLocalWorkSnapshot(
        _FakeOutbox([_entry(OutboxStatus.inProgress)]),
        online: true,
      );

      expect(work.unsynced, 1);
      expect(work.stuck, 0);
      expect(work.hasUnsynced, isTrue);
    });
  });
}
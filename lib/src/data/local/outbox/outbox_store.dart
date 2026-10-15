import 'package:sembast/sembast.dart';

import '../local_database.dart';
import '../local_stores.dart';
import 'outbox_access.dart';
import 'outbox_entry.dart';
import 'outbox_status.dart';

/// Persistence for the transactional outbox.
///
/// [append] takes an explicit [Transaction] so callers can write a business
/// change and its sync command atomically.
class OutboxStore implements OutboxAccess {
  OutboxStore(this._db);

  final LocalDatabase _db;

  Future<void> append(Transaction txn, OutboxEntry entry) =>
      LocalStores.outbox.record(entry.operationId).put(txn, entry.toRecord());

  @override
  Future<List<OutboxEntry>> all() async {
    final snapshots = await LocalStores.outbox.find(_db.db);
    final entries =
        snapshots.map((s) => OutboxEntry.fromRecord(s.value)).toList();
    entries.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return entries;
  }

  /// Entries still awaiting a successful push (including those recovered from a
  /// previous run that crashed mid-flight).
  Future<List<OutboxEntry>> pending() async {
    final entries = await all();
    return entries
        .where((e) =>
            e.syncStatus == OutboxStatus.pending ||
            e.syncStatus == OutboxStatus.retryableFailure ||
            e.syncStatus == OutboxStatus.inProgress)
        .toList();
  }

  Future<OutboxEntry?> byOperationId(String operationId) async {
    final record = await LocalStores.outbox.record(operationId).get(_db.db);
    return record == null ? null : OutboxEntry.fromRecord(record);
  }

  @override
  Future<void> save(OutboxEntry entry) =>
      LocalStores.outbox.record(entry.operationId).put(_db.db, entry.toRecord());

  Future<void> markInProgress(String operationId) => _update(
        operationId,
        (e) => e.copyWith(syncStatus: OutboxStatus.inProgress),
      );

  Future<void> markSynced(String operationId, {Map<String, dynamic>? ack}) =>
      _update(
        operationId,
        (e) => e.copyWith(
          syncStatus: OutboxStatus.synced,
          lastAttemptAt: DateTime.now(),
          clearLastError: true,
          payload: (ack == null || ack.isEmpty)
              ? null
              : {...e.payload, ...ack},
        ),
      );

  Future<void> markRetryable(String operationId, String error) =>
      _update(operationId, (e) {
        return e.copyWith(
          syncStatus: OutboxStatus.retryableFailure,
          attemptCount: e.attemptCount + 1,
          lastAttemptAt: DateTime.now(),
          lastError: error,
        );
      });

  /// Parks an entry for human resolution: the retry budget is spent, or the
  /// entry synced remotely but its local fold-back failed. Parked entries leave
  /// the drain queue and appear on the conflicts screen instead of failing
  /// silently forever.
  /// Whether any unsynced command still references this entity.
  ///
  /// Fold-back handlers consult this before clearing a record's dirty flag:
  /// an ack for an older command must not stamp synced over newer local edits
  /// whose commands have not gone up yet.
  Future<bool> hasOutstandingFor({
    required String entityType,
    required String entityId,
  }) async {
    final entries = await all();
    return entries.any((e) =>
        e.syncStatus != OutboxStatus.synced &&
        e.entityType == entityType &&
        e.entityId == entityId);
  }

  Future<void> markNeedsUserAction(String operationId, String error) =>
      _update(
        operationId,
        (e) => e.copyWith(
          syncStatus: OutboxStatus.requiresUserAction,
          lastAttemptAt: DateTime.now(),
          lastError: error,
        ),
      );

  Future<void> _update(
    String operationId,
    OutboxEntry Function(OutboxEntry) change,
  ) async {
    // Read-modify-write inside one transaction. Separate get/put calls let two
    // interleaved drains compute from the same stale read, so the last writer
    // silently wins — clobbering an incremented attempt count or applying a
    // state change to a record that already moved on.
    await _db.transaction((txn) async {
      final record = LocalStores.outbox.record(operationId);
      final existing = await record.get(txn);
      if (existing == null) return;
      await record.put(txn, change(OutboxEntry.fromRecord(existing)).toRecord());
    });
  }
}

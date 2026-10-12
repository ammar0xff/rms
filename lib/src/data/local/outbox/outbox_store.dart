import 'package:sembast/sembast.dart';

import '../local_database.dart';
import '../local_stores.dart';
import 'outbox_entry.dart';
import 'outbox_status.dart';

/// Persistence for the transactional outbox.
///
/// [append] takes an explicit [Transaction] so callers can write a business
/// change and its sync command atomically.
class OutboxStore {
  OutboxStore(this._db);

  final LocalDatabase _db;

  Future<void> append(Transaction txn, OutboxEntry entry) =>
      LocalStores.outbox.record(entry.operationId).put(txn, entry.toRecord());

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

  Future<void> _update(
    String operationId,
    OutboxEntry Function(OutboxEntry) change,
  ) async {
    final record = LocalStores.outbox.record(operationId);
    final existing = await record.get(_db.db);
    if (existing == null) return;
    await record.put(_db.db, change(OutboxEntry.fromRecord(existing)).toRecord());
  }
}

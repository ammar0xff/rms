import 'package:sembast/sembast.dart';

import '../../domain/update/release_audit_event.dart';
import '../../domain/update/update_audit_sink.dart';
import 'local_database.dart';
import 'local_stores.dart';
import 'update_store_contracts.dart';

/// Durable, append-only persistence for the update lifecycle audit trail.
///
/// Each event is stored under its own [ReleaseAuditEvent.eventId], so the trail
/// is never rewritten and a partially written batch cannot corrupt earlier
/// entries. Events are written in their own transaction: unlike a financial
/// audit row, a lifecycle event describes something that already happened
/// rather than a change that must commit atomically with other state.
class ReleaseAuditLog implements UpdateAuditSink, ReleaseAuditTrail {
  ReleaseAuditLog(this._db);

  final LocalDatabase _db;

  @override
  Future<void> append(ReleaseAuditEvent event) =>
      _db.transaction((txn) => add(txn, event));

  /// Appends an event within a caller-supplied transaction.
  Future<void> add(Transaction txn, ReleaseAuditEvent event) =>
      LocalStores.releaseAuditEvents.record(event.eventId).put(
            txn,
            event.toRecord(),
          );

  /// Most recent events first, capped at [limit].
  @override
  Future<List<ReleaseAuditEvent>> list({int limit = 200}) async {
    final snapshots = await LocalStores.releaseAuditEvents.find(_db.db);
    final events =
        snapshots.map((s) => ReleaseAuditEvent.tryFromRecord(s.value)).whereType<ReleaseAuditEvent>().toList()
          ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    return events.length > limit ? events.sublist(0, limit) : events;
  }

  /// The trail for a single release, most recent first.
  ///
  /// Rows that fail to parse are dropped rather than surfaced, so one corrupt
  /// record cannot make the whole history unreadable.
  Future<List<ReleaseAuditEvent>> forRelease(
    String releaseId, {
    int limit = 200,
  }) async {
    final snapshots =
        await LocalStores.releaseAuditEvents.find(_db.db);
    final events = snapshots
        .map((s) => ReleaseAuditEvent.tryFromRecord(s.value))
        .whereType<ReleaseAuditEvent>()
        .where((e) => e.releaseId == releaseId)
        .toList()
      ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    return events.length > limit ? events.sublist(0, limit) : events;
  }

  Future<int> count() async =>
      (await LocalStores.releaseAuditEvents.find(_db.db)).length;
}
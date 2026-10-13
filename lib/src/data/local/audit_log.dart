import 'package:sembast/sembast.dart';

import '../../domain/models/audit_entry.dart';
import 'local_database.dart';
import 'local_stores.dart';

/// Append-only persistence for the audit trail.
///
/// [append] takes the caller's [Transaction] so an audit row is committed with
/// the operation it describes and can never be lost independently of it.
class AuditLog {
  AuditLog(this._db);

  final LocalDatabase _db;

  Future<void> append(Transaction txn, AuditEntry entry) =>
      LocalStores.audit.record(entry.id).put(txn, entry.toRecord());

  /// Appends an entry in its own transaction.
  Future<void> record(AuditEntry entry) =>
      _db.transaction((txn) => append(txn, entry));

  /// Most recent entries first, capped at [limit].
  Future<List<AuditEntry>> list({int limit = 200}) async {
    final snapshots = await LocalStores.audit.find(_db.db);
    final entries =
        snapshots.map((s) => AuditEntry.fromRecord(s.value)).toList()
          ..sort((a, b) => b.at.compareTo(a.at));
    return entries.length > limit ? entries.sublist(0, limit) : entries;
  }

  Future<int> count() async => (await LocalStores.audit.find(_db.db)).length;
}

import 'package:sembast/sembast.dart';

import '../../local/local_database.dart';
import '../../local/local_stores.dart';
import 'local_migration.dart';

/// The result of bringing the store up to the requested schema version.
class MigrationOutcome {
  const MigrationOutcome({
    required this.fromVersion,
    required this.toVersion,
    required this.applied,
    required this.succeeded,
    this.error,
  });

  final int fromVersion;
  final int toVersion;
  final List<String> applied;
  final bool succeeded;
  final String? error;

  bool get changed => applied.isNotEmpty;
}

/// Applies pending [LocalMigration]s to a [LocalDatabase].
///
/// The version is stored in the `meta` store and advanced only after a step
/// commits, so an interrupted or failed migration leaves the previous version
/// in place. Migrations run in transactions that also write their own version
/// bump, and they never touch the outbox, so pending offline work survives a
/// schema upgrade.
class LocalMigrationRunner {
  LocalMigrationRunner(this._db, this._migrations);

  /// Key under which the applied schema version is stored in [LocalStores.meta].
  static const String versionKey = 'schemaVersion';

  final LocalDatabase _db;
  final List<LocalMigration> _migrations;

  Future<int> currentVersion() async {
    final record = await LocalStores.meta.record(versionKey).get(_db.db);
    final value = record?['value'];
    return value is int ? value : 0;
  }

  Future<MigrationOutcome> run({required int targetVersion}) async {
    final from = await currentVersion();
    if (from >= targetVersion) {
      return MigrationOutcome(
        fromVersion: from,
        toVersion: from,
        applied: const [],
        succeeded: true,
      );
    }

    final pending = _migrations
        .where((m) => m.from >= from && m.to <= targetVersion)
        .toList()
      ..sort((a, b) => a.from.compareTo(b.from));

    final applied = <String>[];
    var current = from;
    for (final migration in pending) {
      if (migration.from != current) {
        // Stop at the first gap; applying later steps against the wrong base is
        // worse than leaving the job for a developer to fix the registry.
        return MigrationOutcome(
          fromVersion: from,
          toVersion: current,
          applied: applied,
          succeeded: false,
          error: 'no migration from v$current (next is v${migration.from})',
        );
      }
      try {
        await _db.transaction((txn) async {
          await migration.run(txn);
          await LocalStores.meta.record(versionKey).put(txn, {
            'value': migration.to,
            'migration': migration.id,
            'updatedAt': DateTime.now().toIso8601String(),
          });
        });
      } catch (error) {
        return MigrationOutcome(
          fromVersion: from,
          toVersion: current,
          applied: applied,
          succeeded: false,
          error: '${migration.id}: $error',
        );
      }
      applied.add(migration.id);
      current = migration.to;
    }

    return MigrationOutcome(
      fromVersion: from,
      toVersion: current,
      applied: applied,
      succeeded: true,
    );
  }
}

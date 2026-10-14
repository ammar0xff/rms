import 'package:sembast/sembast.dart';

import '../../domain/models/update_manifest.dart';
import '../../domain/update/device_update_status.dart';
import '../../domain/update/update_health_checker.dart';
import '../local/local_database.dart';
import '../local/local_stores.dart';
import '../local/migrations/local_migration.dart';
import '../local/migrations/local_migration_registry.dart';
import '../local/migrations/local_migration_runner.dart';

/// Checks that the device is healthy after an update was applied.
///
/// This is the last line of defence before a failed update is reported as
/// rolled back. It deliberately checks the things an upgrade can actually
/// break — that the store still opens, and that the schema version matches what
/// this binary expects — rather than re-running the whole application.
///
/// A health check that cannot reach a verdict reports
/// [UpdateHealthStatus.inconclusive] rather than [UpdateHealthStatus.passed].
/// The coordinator treats anything other than `passed` as a failure, and
/// claiming success on a store that never answered would turn an unrecoverable
/// state into a silent one.
class LocalHealthChecker implements UpdateHealthChecker {
  LocalHealthChecker({
    required this.database,
    required this.expectedSchemaVersion,
    List<LocalMigration>? migrations,
  }) : migrations = migrations ?? defaultLocalMigrations;

  final LocalDatabase database;

  /// The schema version this binary was compiled against.
  final int expectedSchemaVersion;

  final List<LocalMigration> migrations;

  @override
  Future<UpdateHealthStatus> check({required UpdateManifest manifest}) async {
    try {
      // Touches the store. A database that cannot be read at all cannot be
      // trusted with an upgraded schema.
      await LocalStores.meta.find(database.db);

      final version =
          await LocalMigrationRunner(database, migrations).currentVersion();
      if (version != expectedSchemaVersion) return UpdateHealthStatus.failed;

      // A release may publish a target that disagrees with the compiled-in
      // version; that is a publishing error, and the device is not healthy.
      final required = manifest.requiredMigrationVersion;
      if (required != null && required != expectedSchemaVersion) {
        return UpdateHealthStatus.failed;
      }

      return UpdateHealthStatus.passed;
    } catch (_) {
      return UpdateHealthStatus.inconclusive;
    }
  }
}
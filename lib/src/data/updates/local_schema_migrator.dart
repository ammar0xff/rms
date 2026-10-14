import '../../domain/models/update_manifest.dart';
import '../../domain/update/update_migrator.dart';
import '../local/local_database.dart';
import '../local/migrations/local_migration.dart';
import '../local/migrations/local_migration_registry.dart';
import '../local/migrations/local_migration_runner.dart';

/// Applies the local schema migration a release requires.
///
/// Android and desktop install a whole new application, so an upgrade arrives
/// with a new binary that expects a newer local schema. This bridges that gap
/// after the install and before the health check runs.
///
/// The target comes from the manifest's `requiredMigrationVersion`. A release
/// that publishes no requirement is treated as needing nothing, which is the
/// common case: most updates change no schema.
///
/// Migrations never touch the outbox, so unsynced local work survives the
/// upgrade — that is what makes it safe to run this while AC-35's gate has
/// already confirmed the backlog is clear.
class LocalSchemaMigrator implements UpdateMigrator {
  LocalSchemaMigrator({
    required this.database,
    List<LocalMigration>? migrations,
  }) : migrations = migrations ?? defaultLocalMigrations;

  final LocalDatabase database;
  final List<LocalMigration> migrations;

  @override
  Future<MigrationResult> migrate({required UpdateManifest manifest}) async {
    final target = manifest.requiredMigrationVersion;
    if (target == null) return MigrationResult.ok;

    try {
      final runner = LocalMigrationRunner(database, migrations);
      final current = await runner.currentVersion();
      // Already at or past the target: a re-run after a crash, or a release
      // published for an older device.
      if (current >= target) return MigrationResult.ok;

      final outcome = await runner.run(targetVersion: target);
      return outcome.succeeded ? MigrationResult.ok : MigrationResult.failed;
    } catch (_) {
      return MigrationResult.failed;
    }
  }
}
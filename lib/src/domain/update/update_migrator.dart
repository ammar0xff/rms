import '../models/update_manifest.dart';

/// The outcome of a local schema migration.
enum MigrationResult {
  ok('نجح الترحيل'),
  failed('فشل الترحيل');

  const MigrationResult(this.label);

  final String label;
}

/// An abstraction over the local schema migration step run after an install.
abstract class UpdateMigrator {
  Future<MigrationResult> migrate({required UpdateManifest manifest});
}

import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast.dart';
import 'package:rms/src/data/local/local_database.dart';
import 'package:rms/src/data/local/local_stores.dart';
import 'package:rms/src/data/local/migrations/local_migration_runner.dart';
import 'package:rms/src/data/updates/local_health_checker.dart';
import 'package:rms/src/domain/models/update_manifest.dart';
// UpdateHealthStatus is declared here. update_health_checker.dart only imports
// it for its own interface, and an import does not re-export.
import 'package:rms/src/domain/update/device_update_status.dart';

int _seq = 0;

final _sha = 'a' * 64;

UpdateManifest _manifest({int? requiredMigrationVersion}) => UpdateManifest(
      releaseId: 'rel-1',
      version: '1.1.0',
      buildNumber: 42,
      platform: UpdatePlatform.android,
      channel: UpdateChannel.production,
      status: ReleaseStatus.active,
      rolloutPercent: 100,
      severity: UpdateSeverity.optional,
      publishedAt: DateTime(2026, 10, 13),
      requiredMigrationVersion: requiredMigrationVersion,
      artifact: ReleaseArtifact(
        reference: 'https://example.com/app.apk',
        sizeBytes: 1000,
        sha256: _sha,
      ),
    );

Future<LocalDatabase> _memoryDb() => LocalDatabase.memory('rms_health_${_seq++}');

/// Stamps the schema version directly, standing in for a device that has run
/// migrations up to [version].
Future<void> _setVersion(LocalDatabase db, int version) =>
    LocalStores.meta
        .record(LocalMigrationRunner.versionKey)
        .put(db.db, {'value': version});

void main() {
  group('LocalHealthChecker', () {
    test('passes when the store is readable and the schema matches', () async {
      final db = await _memoryDb();
      await _setVersion(db, 5);

      final checker = LocalHealthChecker(database: db, expectedSchemaVersion: 5);

      expect(await checker.check(manifest: _manifest()),
          UpdateHealthStatus.passed);
    });

    // The point of the check: an upgrade that left the schema behind would have
    // the binary reading records it cannot understand.
    test('fails when the store is on an older schema than this binary expects',
        () async {
      final db = await _memoryDb();
      await _setVersion(db, 4);

      final checker = LocalHealthChecker(database: db, expectedSchemaVersion: 5);

      expect(await checker.check(manifest: _manifest()),
          UpdateHealthStatus.failed);
    });

    test('fails when the store is ahead of this binary', () async {
      final db = await _memoryDb();
      await _setVersion(db, 6);

      final checker = LocalHealthChecker(database: db, expectedSchemaVersion: 5);

      expect(await checker.check(manifest: _manifest()),
          UpdateHealthStatus.failed);
    });

    test('fails when the store has never been migrated', () async {
      final db = await _memoryDb();

      // No version stamped: the runner reports 0.
      final checker = LocalHealthChecker(database: db, expectedSchemaVersion: 5);

      expect(await checker.check(manifest: _manifest()),
          UpdateHealthStatus.failed);
    });

    // A release declaring a target the binary disagrees with is a publishing
    // error, and the device is not healthy against it.
    test('fails when the release targets a schema this binary is not', () async {
      final db = await _memoryDb();
      await _setVersion(db, 5);

      final checker = LocalHealthChecker(database: db, expectedSchemaVersion: 5);

      expect(
        await checker.check(manifest: _manifest(requiredMigrationVersion: 6)),
        UpdateHealthStatus.failed,
      );
    });

    test('passes when the release targets the schema this binary expects',
        () async {
      final db = await _memoryDb();
      await _setVersion(db, 5);

      final checker = LocalHealthChecker(database: db, expectedSchemaVersion: 5);

      expect(
        await checker.check(manifest: _manifest(requiredMigrationVersion: 5)),
        UpdateHealthStatus.passed,
      );
    });

    test('ignores a release that names no migration target', () async {
      final db = await _memoryDb();
      await _setVersion(db, 5);

      final checker = LocalHealthChecker(database: db, expectedSchemaVersion: 5);

      expect(await checker.check(manifest: _manifest()),
          UpdateHealthStatus.passed);
    });

    // The coordinator treats anything other than `passed` as a failure, so a
    // checker that could not reach a verdict must say so rather than pass. This
    // is the fail-closed half of the check.
    test('reports inconclusive rather than passed when the store cannot be read',
        () async {
      final db = await _memoryDb();
      await _setVersion(db, 5);
      await db.close();

      final checker = LocalHealthChecker(database: db, expectedSchemaVersion: 5);

      final status = await checker.check(manifest: _manifest());
      expect(status, isNot(UpdateHealthStatus.passed));
      expect(status, UpdateHealthStatus.inconclusive);
    });
  });
}

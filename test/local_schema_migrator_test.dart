import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast.dart';
import 'package:rms/src/data/local/local_database.dart';
import 'package:rms/src/data/local/local_stores.dart';
import 'package:rms/src/data/local/migrations/local_migration.dart';
import 'package:rms/src/data/local/migrations/local_migration_runner.dart';
import 'package:rms/src/data/updates/local_schema_migrator.dart';
import 'package:rms/src/domain/models/update_manifest.dart';
import 'package:rms/src/domain/update/update_migrator.dart';

int _seq = 0;

final _sha = 'a' * 64;

UpdateManifest _manifest({int? requiredMigrationVersion}) => UpdateManifest(
      releaseId: 'android-1.1.0-3',
      version: '1.1.0',
      buildNumber: 3,
      platform: UpdatePlatform.android,
      channel: UpdateChannel.production,
      status: ReleaseStatus.active,
      rolloutPercent: 100,
      severity: UpdateSeverity.optional,
      publishedAt: DateTime(2026, 10, 14),
      requiredMigrationVersion: requiredMigrationVersion,
      artifact: ReleaseArtifact(
        reference: 'https://example.com/app.apk',
        sizeBytes: 1000,
        sha256: _sha,
      ),
    );

Future<LocalDatabase> _memoryDb() =>
    LocalDatabase.memory('rms_migrate_${_seq++}');

Future<void> _setVersion(LocalDatabase db, int version) =>
    LocalStores.meta.record(LocalMigrationRunner.versionKey).put(db.db, {
          'value': version,
        });

/// A migration that records that it ran, by stamping a marker row.
LocalMigration _marker(int from, int to, {bool explode = false}) => LocalMigration(
      from: from,
      to: to,
      id: 'v$from->$to',
      run: (Transaction txn) async {
        if (explode) throw StateError('migration blew up');
        await LocalStores.meta.record('migrated_$from').put(txn, {'ok': true});
      },
    );

void main() {
  group('LocalSchemaMigrator', () {
    // Most releases change no schema, so this is the common path and it must
    // not touch the database at all.
    test('does nothing when the release requires no migration', () async {
      final db = await _memoryDb();
      await _setVersion(db, 5);

      final result = await LocalSchemaMigrator(
        database: db,
        migrations: [_marker(5, 6)],
      ).migrate(manifest: _manifest());

      expect(result, MigrationResult.ok);
      // Untouched: the marker for v5->v6 was never written.
      expect(await LocalStores.meta.record('migrated_5').get(db.db), isNull);
      expect(await LocalStores.meta.record(LocalMigrationRunner.versionKey).get(db.db),
          containsPair('value', 5));
    });

    test('applies the migrations a release requires', () async {
      final db = await _memoryDb();
      await _setVersion(db, 5);

      final result = await LocalSchemaMigrator(
        database: db,
        migrations: [_marker(5, 6), _marker(6, 7)],
      ).migrate(manifest: _manifest(requiredMigrationVersion: 7));

      expect(result, MigrationResult.ok);
      expect(await LocalStores.meta.record('migrated_5').get(db.db), isNotNull);
      expect(await LocalStores.meta.record('migrated_6').get(db.db), isNotNull);
      expect(
        await LocalStores.meta.record(LocalMigrationRunner.versionKey).get(db.db),
        containsPair('value', 7),
      );
    });

    // A crash mid-upgrade leaves the version stamped partway. Re-running must
    // pick up from there rather than refuse or reapply from scratch.
    test('resumes a partially applied upgrade', () async {
      final db = await _memoryDb();
      await _setVersion(db, 6);

      final result = await LocalSchemaMigrator(
        database: db,
        migrations: [_marker(5, 6), _marker(6, 7)],
      ).migrate(manifest: _manifest(requiredMigrationVersion: 7));

      expect(result, MigrationResult.ok);
      // The first step was already applied, so it is not run again.
      expect(await LocalStores.meta.record('migrated_5').get(db.db), isNull);
      expect(await LocalStores.meta.record('migrated_6').get(db.db), isNotNull);
    });

    // A release published for an older device must not attempt to downgrade.
    test('does nothing when the store is already past the target', () async {
      final db = await _memoryDb();
      await _setVersion(db, 9);

      final result = await LocalSchemaMigrator(
        database: db,
        migrations: [_marker(5, 6)],
      ).migrate(manifest: _manifest(requiredMigrationVersion: 7));

      expect(result, MigrationResult.ok);
      expect(await LocalStores.meta.record('migrated_5').get(db.db), isNull);
      expect(
        await LocalStores.meta.record(LocalMigrationRunner.versionKey).get(db.db),
        containsPair('value', 9),
      );
    });

    test('reports failure when a migration throws', () async {
      final db = await _memoryDb();
      await _setVersion(db, 5);

      final result = await LocalSchemaMigrator(
        database: db,
        migrations: [_marker(5, 6, explode: true)],
      ).migrate(manifest: _manifest(requiredMigrationVersion: 6));

      // The health check must not be told this device is fine.
      expect(result, MigrationResult.failed);
    });

    // A gap in the registry means the device cannot reach the target by any
    // honest route. Stopping beats applying a later step to the wrong base.
    test('reports failure when the registry has a gap', () async {
      final db = await _memoryDb();
      await _setVersion(db, 5);

      final result = await LocalSchemaMigrator(
        database: db,
        migrations: [_marker(6, 7)],
      ).migrate(manifest: _manifest(requiredMigrationVersion: 7));

      expect(result, MigrationResult.failed);
      expect(await LocalStores.meta.record('migrated_6').get(db.db), isNull);
    });

    test('reports failure when the database cannot be read', () async {
      final db = await _memoryDb();
      await _setVersion(db, 5);
      await db.close();

      final result = await LocalSchemaMigrator(
        database: db,
        migrations: [_marker(5, 6)],
      ).migrate(manifest: _manifest(requiredMigrationVersion: 6));

      expect(result, MigrationResult.failed);
    });
  });
}

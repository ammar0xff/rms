import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/data/local/local_database.dart';
import 'package:rms/src/data/local/local_stores.dart';
import 'package:rms/src/data/repositories/local_update_repository.dart';
import 'package:rms/src/domain/models/update_manifest.dart';
import 'package:sembast/sembast.dart';

int _seq = 0;

final _sha = List.filled(64, 'a').join();

UpdateManifest _manifest() => UpdateManifest(
      releaseId: 'rel-1',
      version: '0.9.0',
      buildNumber: 2,
      platform: UpdatePlatform.web,
      channel: UpdateChannel.production,
      status: ReleaseStatus.active,
      rolloutPercent: 100,
      severity: UpdateSeverity.recommended,
      publishedAt: DateTime(2026, 10, 13),
      artifact: ReleaseArtifact(
        reference: 'releases/rms-0.9.0.pkg',
        sizeBytes: 1024,
        sha256: _sha,
      ),
    );

void main() {
  late LocalDatabase db;

  setUp(() async {
    db = await LocalDatabase.memory('rms_update_${_seq++}');
  });

  tearDown(() => db.close());

  test('reads null before anything is cached', () async {
    expect(await LocalUpdateRepository(db).cached(), isNull);
  });

  test('caches and reads back the manifest', () async {
    final repo = LocalUpdateRepository(db);
    await repo.cache(_manifest());

    final cached = await repo.cached();
    expect(cached, isNotNull);
    expect(cached!.releaseId, 'rel-1');
    expect(cached.version, '0.9.0');
    expect(cached.platform, UpdatePlatform.web);
    expect(cached.severity, UpdateSeverity.recommended);
    expect(cached.artifact.sha256, _sha);
  });

  test('treats a malformed cached document as absent', () async {
    await LocalStores.config.record(LocalUpdateRepository.manifestKey).put(db.db, {
      'releaseId': 'rel-1',
      'version': 'not-a-version',
      'buildNumber': 2,
      'platform': 'web',
      'channel': 'production',
      'status': 'active',
      'severity': 'optional',
      'rolloutPercent': 100,
      'publishedAt': '2026-10-13T00:00:00.000',
      'artifact': {'reference': 'x', 'sizeBytes': 1, 'sha256': 'abc'},
      'manifestSchemaVersion': 1,
    });

    expect(await LocalUpdateRepository(db).cached(), isNull);
  });
}

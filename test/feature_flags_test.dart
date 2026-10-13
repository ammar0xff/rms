import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/data/local/local_database.dart';
import 'package:rms/src/data/repositories/local_feature_flag_repository.dart';
import 'package:rms/src/domain/models/release_manifest.dart';

int _seq = 0;

Future<LocalDatabase> _memoryDb() => LocalDatabase.memory('rms_flags_${_seq++}');

void main() {
  late LocalDatabase db;
  late LocalFeatureFlagRepository repo;

  setUp(() async {
    db = await _memoryDb();
    repo = LocalFeatureFlagRepository(db);
  });

  tearDown(() => db.close());

  test('caches and reads the release manifest', () async {
    expect(await repo.manifest(), isNull);

    await repo.cacheManifest(
      ReleaseManifest(
        channel: 'stable',
        version: '0.3.0',
        minSupportedVersion: '0.2.0',
        rolloutPercent: 25,
        mandatory: false,
        publishedAt: DateTime(2026, 10, 13),
        flags: const [
          FeatureFlag(key: 'a', label: 'A', enabled: true, scope: 'عام'),
          FeatureFlag(key: 'b', label: 'B', enabled: false),
        ],
      ),
    );

    final manifest = await repo.manifest();
    expect(manifest?.version, '0.3.0');
    expect(manifest?.rolloutPercent, 25);
    expect(manifest?.flags, hasLength(2));

    expect(await repo.isEnabled('a'), isTrue);
    expect(await repo.isEnabled('b'), isFalse);
    expect(await repo.isEnabled('missing', fallback: true), isTrue);
    expect(await repo.isEnabled('missing'), isFalse);
  });

  test('falls back safely when no manifest is cached', () async {
    expect(await repo.isEnabled('anything'), isFalse);
    expect(await repo.isEnabled('anything', fallback: true), isTrue);
  });
}

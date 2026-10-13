import '../../domain/models/release_manifest.dart';
import '../local/local_database.dart';
import '../local/local_stores.dart';
import 'feature_flag_repository.dart';

/// Stores the release manifest as a single cached configuration document, so
/// flags and the update channel survive restarts and long offline stretches.
class LocalFeatureFlagRepository implements FeatureFlagRepository {
  LocalFeatureFlagRepository(this._db);

  final LocalDatabase _db;

  static const String manifestKey = 'releaseManifest';

  @override
  Future<ReleaseManifest?> manifest() async {
    final record = await LocalStores.config.record(manifestKey).get(_db.db);
    return record == null ? null : ReleaseManifest.fromRecord(record);
  }

  @override
  Future<void> cacheManifest(ReleaseManifest manifest) =>
      LocalStores.config.record(manifestKey).put(_db.db, manifest.toRecord());

  @override
  Future<bool> isEnabled(String key, {bool fallback = false}) async {
    final cached = await manifest();
    return cached?.isEnabled(key, fallback: fallback) ?? fallback;
  }
}

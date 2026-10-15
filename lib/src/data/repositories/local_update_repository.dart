import 'package:sembast/sembast.dart';

import '../../domain/models/update_manifest.dart';
import '../local/local_database.dart';
import '../local/local_stores.dart';
import 'update_repository.dart';

/// Caches the server-published release manifest in the config store.
///
/// Keeping it locally means the client can classify a release (up to date,
/// optional, recommended, mandatory or ineligible) while offline; only fetching
/// the verified artifact needs connectivity.
class LocalUpdateRepository implements UpdateRepository {
  LocalUpdateRepository(this._db);

  final LocalDatabase _db;

  static const String manifestKey = 'updateManifest';

  @override
  Future<UpdateManifest?> cached() async {
    final record = await LocalStores.config.record(manifestKey).get(_db.db);
    if (record == null) return null;
    // A malformed or newer-schema document is treated as absent rather than
    // partially honoured.
    return UpdateManifest.parse(record).manifest;
  }

  @override
  Future<void> cache(UpdateManifest manifest) =>
      LocalStores.config.record(manifestKey).put(_db.db, manifest.toRecord());

  @override
  Future<void> clear() =>
      LocalStores.config.record(manifestKey).delete(_db.db);
}

import 'package:sembast/sembast.dart';

import '../../domain/update/update_acknowledgement.dart';
import 'local_database.dart';
import 'local_stores.dart';

/// Persists the operator's acknowledgement of stuck local work.
///
/// Shares the `config` store with the cached manifest and the device update
/// status, each under its own key, so none can clobber another and no schema
/// migration is needed.
class UpdateAcknowledgementStore {
  UpdateAcknowledgementStore(this._db);

  final LocalDatabase _db;

  static const String acknowledgementKey = 'updateAcknowledgement';

  /// The stored acknowledgement, or null when none exists or the row is
  /// malformed. A corrupt row is treated as absent so the gate falls back to
  /// requiring a fresh acknowledgement.
  Future<UpdateAcknowledgement?> load() async {
    final record = await LocalStores.config
        .record(acknowledgementKey)
        .get(_db.db);
    if (record == null) return null;
    return UpdateAcknowledgement.tryFromRecord(record);
  }

  Future<void> save(UpdateAcknowledgement acknowledgement) => LocalStores.config
      .record(acknowledgementKey)
      .put(_db.db, acknowledgement.toRecord());
}

import 'package:sembast/sembast.dart';

import '../../domain/models/facility_settings.dart';
import '../local/local_database.dart';
import '../local/local_stores.dart';

/// Terminal facility profile persistence. Single record, local-first; no
/// outbox entry (terminal-local preferences, not synced data).
class LocalFacilityRepository {
  LocalFacilityRepository(this._db);

  final LocalDatabase _db;

  static const _key = 'facility';

  Future<FacilitySettings> load() async {
    final existing =
        await LocalStores.facility.record(_key).get(_db.db);
    if (existing == null) return const FacilitySettings();
    return FacilitySettings.fromRecord(existing);
  }

  Future<FacilitySettings> save(FacilitySettings settings) async {
    await LocalStores.facility.record(_key).put(_db.db, settings.toRecord());
    return settings;
  }
}

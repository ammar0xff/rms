import 'package:sembast/sembast.dart';

import '../../domain/update/device_update_status.dart';
import 'local_database.dart';
import 'local_stores.dart';
import 'update_store_contracts.dart';

/// Persists the device's last known update status (AC-31+).
///
/// Lives in the existing `config` store alongside the cached manifest, so it
/// needs no schema migration. Persisting the status means a device that was
/// rebooted mid-update still reports what it was doing, and an operator can see
/// after the fact whether an install needs a rollback.
class LocalUpdateStatusStore implements UpdateStatusStore {
  LocalUpdateStatusStore(this._db);

  final LocalDatabase _db;

  static const String statusKey = 'deviceUpdateStatus';

  /// The last recorded status, or null when none was stored or the row is
  /// malformed. A corrupt row is treated as absent rather than partially
  /// honoured, matching [LocalUpdateRepository]'s handling of the manifest.
  @override
  Future<DeviceUpdateStatus?> load() async {
    final record = await LocalStores.config.record(statusKey).get(_db.db);
    if (record == null) return null;
    return DeviceUpdateStatus.tryFromRecord(record);
  }

  @override
  Future<void> save(DeviceUpdateStatus status) =>
      LocalStores.config.record(statusKey).put(_db.db, status.toRecord());
}
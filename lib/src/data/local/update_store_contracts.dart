import '../../domain/update/device_update_status.dart';
import '../../domain/update/release_audit_event.dart';
import '../../domain/update/update_acknowledgement.dart';

/// Read/write access to the device's last known update status.
///
/// The settings screen depends on this contract rather than the Sembast
/// implementation so it can be exercised with a fake. Every other subsystem in
/// the update flow follows the same rule: the domain declares the surface, the
/// data layer supplies the storage.
abstract class UpdateStatusStore {
  /// The last recorded status, or null when none exists or the row is malformed.
  Future<DeviceUpdateStatus?> load();

  Future<void> save(DeviceUpdateStatus status);
}

/// Read access to the append-only update lifecycle audit trail.
///
/// Writing already has a contract in [UpdateAuditSink]; this is the read side
/// the settings screen needs to show an operator what happened.
abstract class ReleaseAuditTrail {
  /// Most recent events first, capped at [limit].
  Future<List<ReleaseAuditEvent>> list({int limit = 200});
}

/// Read/write access to the operator's acknowledgement of stuck local work.
abstract class UpdateAcknowledgementStore {
  /// The stored acknowledgement, or null when none exists or the row is
  /// malformed.
  Future<UpdateAcknowledgement?> load();

  Future<void> save(UpdateAcknowledgement acknowledgement);
}
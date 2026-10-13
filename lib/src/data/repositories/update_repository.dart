import '../../domain/models/update_manifest.dart';

/// Local-first access to the release manifest this device may install.
///
/// The manifest is cached as a single configuration document so the update
/// decision stays available offline; the backend remains authoritative and only
/// ever publishes newer documents.
abstract class UpdateRepository {
  /// The last release manifest cached on this device, or null when none was
  /// stored (or when the stored document was rejected as malformed).
  Future<UpdateManifest?> cached();

  /// Replaces the cached manifest with [manifest].
  Future<void> cache(UpdateManifest manifest);
}

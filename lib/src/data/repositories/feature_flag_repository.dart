import '../../domain/models/release_manifest.dart';

/// Cached, server-authoritative release configuration.
abstract class FeatureFlagRepository {
  /// The last manifest cached on this device, or null when none was stored.
  Future<ReleaseManifest?> manifest();

  Future<void> cacheManifest(ReleaseManifest manifest);

  /// Whether [key] is enabled in the cached manifest (or [fallback] when the
  /// manifest or key is absent).
  Future<bool> isEnabled(String key, {bool fallback = false});
}

import '../repositories/update_repository.dart';
import 'remote_update_source.dart';

/// Why a refresh ended the way it did.
enum UpdateRefreshOutcome {
  /// A newer manifest was fetched and cached.
  updated('تم تحديث بيان الإصدار'),

  /// The backend offered nothing newer, so the cache was left alone.
  unchanged('لا يوجد إصدار أحدث'),

  /// The backend could not be reached; the cached document still stands.
  offline('تعذّر الوصول إلى الخادم'),

  /// The device is configured to ignore published releases.
  skipped('التحديثات غير مفعّلة على هذه المنصة');

  const UpdateRefreshOutcome(this.label);

  final String label;
}

/// Brings the cached release manifest up to date from the backend.
///
/// The cache is authoritative and is never cleared. A fetch that fails, returns
/// nothing, or returns something older leaves the device exactly as it was — an
/// update check is a convenience, never a dependency. This is what lets the app
/// start and classify releases with no connectivity at all.
class UpdateRefreshService {
  const UpdateRefreshService({
    required this.remote,
    required this.cache,
    this.artifactDeliverySupported = true,
  });

  final RemoteUpdateSource remote;
  final UpdateRepository cache;

  /// False on platforms that take no release artifact, which then skip polling.
  final bool artifactDeliverySupported;

  Future<UpdateRefreshOutcome> refresh() async {
    if (!artifactDeliverySupported) return UpdateRefreshOutcome.skipped;

    final RemoteUpdateResult result;
    try {
      result = await remote.fetch();
    } catch (_) {
      // The contract says implementations do not throw; a source that breaks it
      // must still not be able to clear a good cache.
      return UpdateRefreshOutcome.offline;
    }

    if (result.unreachable) return UpdateRefreshOutcome.offline;

    final incoming = result.manifest;
    if (incoming == null) return UpdateRefreshOutcome.unchanged;

    final current = await cache.cached();
    if (current != null && incoming.buildNumber <= current.buildNumber) {
      // Never regress: a stale or replayed document must not downgrade a device
      // that already holds a newer release.
      return UpdateRefreshOutcome.unchanged;
    }

    await cache.cache(incoming);
    return UpdateRefreshOutcome.updated;
  }
}
import 'pwa_cache_interface.dart';

PwaCacheTransport createPwaCacheTransport() => _StubPwaCacheTransport();

class _StubPwaCacheTransport implements PwaCacheTransport {
  @override
  void clearCacheAndReload() {
    // No-op on mobile/desktop platforms
  }
}

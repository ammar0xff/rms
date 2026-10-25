import 'pwa_cache_interface.dart';
import 'pwa_cache_stub.dart'
    if (dart.library.js_interop) 'pwa_cache_web.dart';

class PwaCacheService {
  PwaCacheService._();
  static final PwaCacheService instance = PwaCacheService._();

  static final PwaCacheTransport _transport = createPwaCacheTransport();

  void clearCacheAndReload() {
    _transport.clearCacheAndReload();
  }
}

import 'dart:js_interop';
import 'pwa_cache_interface.dart';

@JS('pieClearCacheAndReload')
external bool _pieClearCacheAndReload();

PwaCacheTransport createPwaCacheTransport() => _WebPwaCacheTransport();

class _WebPwaCacheTransport implements PwaCacheTransport {
  @override
  void clearCacheAndReload() {
    try {
      _pieClearCacheAndReload();
    } catch (_) {}
  }
}

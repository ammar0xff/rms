import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'app_version.dart';

/// Reads the running version from the platform and records it on [AppVersion].
///
/// The channel is the same one the update installer uses, rather than a second
/// bridge: both need the installed package, and one channel keeps the native
/// side to a single handler.
abstract final class AppVersionReader {
  static const MethodChannel channel = MethodChannel('dev.rms.app/update');

  /// Populates [AppVersion] from the installed package.
  ///
  /// Best-effort by design. On a platform with no handler — web, desktop, or a
  /// test host — the compiled values stand, which is why they exist at all.
  /// Failing to read a version must never stop the app from starting; it is a
  /// cosmetic loss until an update is actually published, and by then the
  /// fallback is the thing that is stale.
  static Future<void> hydrate({MethodChannel? channel}) async {
    if (kIsWeb) return;
    try {
      final reply =
          await (channel ?? AppVersionReader.channel).invokeMapMethod<String, Object?>('appVersion');
      final version = reply?['versionName'];
      final code = reply?['versionCode'];
      if (version is! String || code is! int) return;
      AppVersion.apply(version: version, build: code);
    } on MissingPluginException {
      // No native handler on this platform.
    } on PlatformException {
      // The package could not be read; fall back silently.
    }
  }
}

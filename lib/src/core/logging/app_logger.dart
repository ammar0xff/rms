import 'package:flutter/foundation.dart';

/// Minimal structured logger. Diagnostics must never leak secrets, so message
/// interpolation is done by callers with non-sensitive values only.
abstract final class AppLogger {
  static void info(String message) => _emit('INFO', message);
  static void warn(String message) => _emit('WARN', message);
  static void error(String message, [Object? error, StackTrace? stackTrace]) {
    _emit('ERROR', message);
    if (error != null && kDebugMode) {
      debugPrint('  cause: $error');
    }
    if (stackTrace != null && kDebugMode) {
      debugPrint('$stackTrace');
    }
  }

  static void _emit(String level, String message) {
    if (kDebugMode) {
      debugPrint('[$level] $message');
    }
  }
}

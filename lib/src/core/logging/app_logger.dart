import 'package:flutter/foundation.dart';

/// Minimal structured logger. Diagnostics must never leak secrets, so message
/// interpolation is done by callers with non-sensitive values only.
///
/// Every line is also kept in a bounded in-memory ring ([recentLines]) that the
/// settings diagnostics card renders. Release builds print nothing anywhere,
/// so without the buffer a device with a broken migration or failed Firebase
/// init would show misleading screens with zero diagnosability.
abstract final class AppLogger {
  static final List<String> _buffer = [];

  /// How many recent lines are kept. Bounded so a chatty loop cannot grow the
  /// process without limit.
  static const int bufferCap = 200;

  /// Newest last. The diagnostics card reads this.
  static List<String> recentLines({int limit = 40}) => List.unmodifiable(
        _buffer.length <= limit
            ? _buffer
            : _buffer.sublist(_buffer.length - limit),
      );

  static void info(String message) => _emit('INFO', message);
  static void warn(String message) => _emit('WARN', message);
  static void error(String message, [Object? error, StackTrace? stackTrace]) {
    _emit('ERROR', message);
    if (error != null) {
      _record('  cause: $error');
      if (kDebugMode) debugPrint('  cause: $error');
    }
    if (stackTrace != null) {
      _record('  $stackTrace'.split('\n').take(5).join('\n'));
      if (kDebugMode) debugPrint('$stackTrace');
    }
  }

  static void _emit(String level, String message) {
    _record('[$level] $message');
    if (kDebugMode) {
      debugPrint('[$level] $message');
    }
  }

  static void _record(String line) {
    _buffer.add(line);
    if (_buffer.length > bufferCap) {
      _buffer.removeRange(0, _buffer.length - bufferCap);
    }
  }
}

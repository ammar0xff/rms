import 'sync_engine.dart';

/// Serializes sync passes so overlapping connectivity events never run the
/// engine concurrently.
class SyncCoordinator {
  SyncCoordinator({required SyncEngine engine}) : _engine = engine;

  final SyncEngine _engine;
  bool _running = false;

  bool get isSyncing => _running;

  /// Runs one drain pass, or returns 0 if a pass is already in flight.
  Future<int> requestSync() async {
    if (_running) return 0;
    _running = true;
    try {
      return await _engine.drain();
    } finally {
      _running = false;
    }
  }
}

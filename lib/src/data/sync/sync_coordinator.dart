import 'sync_engine.dart';

/// Serializes sync passes so overlapping connectivity events never run the
/// engine concurrently.
class SyncCoordinator {
  SyncCoordinator({required SyncEngine engine}) : _engine = engine;

  final SyncEngine _engine;
  bool _running = false;
  bool _rerunRequested = false;

  bool get isSyncing => _running;

  /// Runs one drain pass, or returns 0 if a pass is already in flight.
  /// If another sync is requested while in flight, automatically performs
  /// a follow-up drain pass so no queued item is ever delayed.
  Future<int> requestSync() async {
    if (_running) {
      _rerunRequested = true;
      return 0;
    }
    _running = true;
    var totalApplied = 0;
    try {
      do {
        _rerunRequested = false;
        totalApplied += await _engine.drain();
      } while (_rerunRequested);
      return totalApplied;
    } finally {
      _running = false;
    }
  }
}

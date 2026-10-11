import 'dart:async';

import 'connectivity_monitor.dart';
import 'sync_coordinator.dart';

/// Drives the sync engine from connectivity changes.
///
/// [start] does a catch-up pass for anything queued while the app was closed,
/// then runs a pass every time the link comes back. Passes are funnelled through
/// [SyncCoordinator] so overlapping events never run concurrently.
class SyncService {
  SyncService({
    required SyncCoordinator coordinator,
    required ConnectivityMonitor connectivity,
  })  : _coordinator = coordinator,
        _connectivity = connectivity;

  final SyncCoordinator _coordinator;
  final ConnectivityMonitor _connectivity;

  StreamSubscription<bool>? _subscription;
  bool _online = true;

  /// Latest observed online state.
  bool get isOnline => _online;

  Future<void> start() async {
    _online = await _connectivity.isOnline;
    _subscription ??= _connectivity.onChanged.listen(_onConnectivity);
    if (_online) {
      unawaited(requestSync());
    }
  }

  Future<int> requestSync() => _coordinator.requestSync();

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  void _onConnectivity(bool online) {
    _online = online;
    if (online) {
      unawaited(requestSync());
    }
  }
}

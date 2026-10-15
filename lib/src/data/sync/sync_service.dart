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
    this.onSynced,
  })  : _coordinator = coordinator,
        _connectivity = connectivity;

  final SyncCoordinator _coordinator;
  final ConnectivityMonitor _connectivity;
  final void Function(int applied)? onSynced;

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

  Future<int> requestSync() async {
    // Never drain while known-offline: every failure would burn one attempt
    // off each entry's budget for a network that was never actually tried.
    if (!_online) return 0;
    final applied = await _coordinator.requestSync();
    if (onSynced != null) {
      onSynced!(applied);
    }
    return applied;
  }

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

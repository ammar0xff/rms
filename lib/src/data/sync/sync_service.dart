import 'dart:async';

import '../local/outbox/outbox_store.dart';
import 'connectivity_monitor.dart';
import 'sync_coordinator.dart';

/// Drives the sync engine from connectivity changes, outbox writes, and background heartbeat.
///
/// [start] does a catch-up pass for anything queued while the app was closed,
/// then runs continuous auto-sync passes:
/// 1. Immediately whenever new outbox entries are appended
/// 2. Continuously on a background heartbeat interval
/// 3. Whenever network connectivity returns
/// Passes are funnelled through [SyncCoordinator] so overlapping events never run concurrently.
class SyncService {
  SyncService({
    required SyncCoordinator coordinator,
    required ConnectivityMonitor connectivity,
    OutboxStore? outbox,
    Duration autoSyncInterval = const Duration(seconds: 4),
    this.onSynced,
  })  : _coordinator = coordinator,
        _connectivity = connectivity,
        _outbox = outbox,
        _autoSyncInterval = autoSyncInterval {
    _outbox?.onEntryAdded = _onOutboxEntryAdded;
  }

  /// Toggle for periodic heartbeat in test environments.
  static bool enablePeriodicHeartbeat = true;

  final SyncCoordinator _coordinator;
  final ConnectivityMonitor _connectivity;
  final OutboxStore? _outbox;
  final Duration _autoSyncInterval;
  final void Function(int applied)? onSynced;

  StreamSubscription<bool>? _subscription;
  Timer? _heartbeatTimer;
  bool _online = true;

  /// Latest observed online state.
  bool get isOnline => _online;

  Future<void> start() async {
    _online = await _connectivity.isOnline;
    _subscription ??= _connectivity.onChanged.listen(_onConnectivity);
    if (enablePeriodicHeartbeat) {
      _startHeartbeat();
    }
    if (_online) {
      unawaited(requestSync());
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_autoSyncInterval, (_) {
      if (_online) {
        unawaited(requestSync());
      }
    });
  }

  void _onOutboxEntryAdded() {
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
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    await _subscription?.cancel();
    _subscription = null;
    if (_outbox?.onEntryAdded == _onOutboxEntryAdded) {
      _outbox?.onEntryAdded = null;
    }
  }

  void _onConnectivity(bool online) {
    _online = online;
    if (online) {
      unawaited(requestSync());
    }
  }
}

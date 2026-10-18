import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../data/local/outbox/outbox_status.dart';
import '../../data/local/outbox/outbox_store.dart';
import '../../data/sync/connectivity_monitor.dart';
import '../../data/sync/sync_service.dart';

class SyncMonitor extends ChangeNotifier {
  SyncMonitor._() {
    _initConnectivity();
  }
  static final SyncMonitor instance = SyncMonitor._();

  SyncService? _sync;
  OutboxStore? _outbox;
  ConnectivityMonitor? _connectivity;
  StreamSubscription<bool>? _connSub;
  Timer? _pollTimer;

  bool _systemOnline = true;
  bool _simulatedOffline = false;
  int _pending = 0;
  int _failed = 0;
  int _conflicts = 0;
  int _synced = 0;
  int _total = 0;
  DateTime? _lastSyncAt;

  bool get online => !_simulatedOffline && (_sync != null ? _sync!.isOnline : _systemOnline);
  bool get isSimulatedOffline => _simulatedOffline;
  int get pending => _pending;
  int get failed => _failed;
  int get conflicts => _conflicts;
  int get synced => _synced;
  int get total => _total;
  Duration get sinceLastSync => _lastSyncAt == null
      ? Duration.zero
      : DateTime.now().difference(_lastSyncAt!);

  static bool enablePolling = true;
  static bool enableConnectivity = true;

  void _initConnectivity() {
    if (!enableConnectivity) {
      _systemOnline = true;
      return;
    }
    try {
      // If Flutter bindings are not initialized (e.g. pure unit tests), skip platform channels
      WidgetsBinding.instance;
      _connectivity = ConnectivityMonitor();
      _connectivity!.isOnline.then((val) {
        _systemOnline = val;
        refresh();
      }).catchError((_) {});
      _connSub = _connectivity!.onChanged.listen(
        (online) {
          _systemOnline = online;
          refresh();
        },
        onError: (_) {},
        cancelOnError: false,
      );
    } catch (_) {
      // Bindings not initialized or platform channel unavailable
    }
  }

  void attach({SyncService? sync, OutboxStore? outbox}) {
    _sync = sync;
    _outbox = outbox;
    _pollTimer?.cancel();
    if (enablePolling) {
      _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => refresh());
    }
    refresh();
  }

  void detach() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _sync = null;
    _outbox = null;
  }

  Future<void> refresh() async {
    final outbox = _outbox;
    if (outbox == null) {
      _pending = 0;
      _failed = 0;
      _conflicts = 0;
      _synced = 0;
      _total = 0;
      _lastSyncAt = null;
    } else {
      final entries = await outbox.all();
      _total = entries.length;
      _pending = entries
          .where((e) =>
              e.syncStatus == OutboxStatus.pending ||
              e.syncStatus == OutboxStatus.retryableFailure ||
              e.syncStatus == OutboxStatus.inProgress)
          .length;
      _failed = entries
          .where((e) =>
              e.syncStatus == OutboxStatus.permanentlyRejected ||
              e.syncStatus == OutboxStatus.requiresUserAction)
          .length;
      _conflicts = entries.where((e) => e.syncStatus == OutboxStatus.conflict).length;
      final synced = entries.where((e) => e.syncStatus == OutboxStatus.synced).toList();
      _synced = synced.length;
      if (synced.isNotEmpty) {
        _lastSyncAt = synced.map((e) => e.lastAttemptAt ?? e.createdAt).reduce((a, b) => a.isAfter(b) ? a : b);
      } else {
        _lastSyncAt = null;
      }
    }
    notifyListeners();
  }

  void toggleConnectivity() {
    _simulatedOffline = !_simulatedOffline;
    refresh();
  }

  void setSimulatedOffline(bool offline) {
    if (_simulatedOffline != offline) {
      _simulatedOffline = offline;
      refresh();
    }
  }

  void simulateSync() {
    _pending = 0;
    _failed = 0;
    _conflicts = 0;
    _lastSyncAt = DateTime.now();
    notifyListeners();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _connSub?.cancel();
    super.dispose();
  }
}

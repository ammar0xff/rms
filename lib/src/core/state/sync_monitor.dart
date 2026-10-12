import 'package:flutter/foundation.dart';

import '../../data/local/outbox/outbox_status.dart';
import '../../data/local/outbox/outbox_store.dart';
import '../../data/sync/sync_service.dart';

class SyncMonitor extends ChangeNotifier {
  SyncMonitor._();
  static final SyncMonitor instance = SyncMonitor._();

  SyncService? _sync;
  OutboxStore? _outbox;

  bool _online = false;
  int _pending = 0;
  int _failed = 0;
  int _conflicts = 0;
  int _synced = 0;
  int _total = 0;
  DateTime? _lastSyncAt;

  bool get online => _online;
  int get pending => _pending;
  int get failed => _failed;
  int get conflicts => _conflicts;
  int get synced => _synced;
  int get total => _total;
  Duration get sinceLastSync => _lastSyncAt == null
      ? Duration.zero
      : DateTime.now().difference(_lastSyncAt!);

  void attach({SyncService? sync, OutboxStore? outbox}) {
    _sync = sync;
    _outbox = outbox;
    refresh();
  }

  Future<void> refresh() async {
    _online = _sync?.isOnline ?? false;
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
      _failed = entries.where((e) => e.syncStatus == OutboxStatus.permanentlyRejected).length;
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
    _online = !_online;
    notifyListeners();
  }

  void simulateSync() {
    _pending = 0;
    _failed = 0;
    _conflicts = 0;
    _lastSyncAt = DateTime.now();
    notifyListeners();
  }
}

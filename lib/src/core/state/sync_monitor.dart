import 'package:flutter/foundation.dart';

class SyncMonitor extends ChangeNotifier {
  SyncMonitor._();
  static final SyncMonitor instance = SyncMonitor._();

  bool online = false;
  int pending = 24;
  int failed = 3;
  int conflicts = 2;
  Duration sinceLastSync = const Duration(minutes: 12);

  void toggleConnectivity() {
    online = !online;
    notifyListeners();
  }

  void simulateSync() {
    pending = 0;
    failed = 0;
    sinceLastSync = Duration.zero;
    notifyListeners();
  }
}

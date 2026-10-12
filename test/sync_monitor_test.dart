import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/core/state/sync_monitor.dart';

void main() {
  test('SyncMonitor initial state and simulateSync', () {
    final m = SyncMonitor.instance;
    m.simulateSync();
    expect(m.pending, 0);
    expect(m.failed, 0);
    expect(m.conflicts, 0);
    expect(m.sinceLastSync.inSeconds, lessThan(2));
  });

  test('toggleConnectivity flips online', () {
    final m = SyncMonitor.instance;
    final before = m.online;
    m.toggleConnectivity();
    expect(m.online, !before);
  });
}

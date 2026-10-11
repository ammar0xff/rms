import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/data/sync/connectivity_monitor.dart';

void main() {
  group('ConnectivityMonitor.hasConnection', () {
    test('reports false only when no link is present', () {
      expect(
        ConnectivityMonitor.hasConnection([ConnectivityResult.none]),
        isFalse,
      );
      expect(
        ConnectivityMonitor.hasConnection([ConnectivityResult.wifi]),
        isTrue,
      );
      expect(
        ConnectivityMonitor.hasConnection(
          [ConnectivityResult.none, ConnectivityResult.mobile],
        ),
        isTrue,
      );
    });
  });

  group('ConnectivityMonitor', () {
    test('isOnline reflects the injected check', () async {
      expect(
        await ConnectivityMonitor(
          check: () async => [ConnectivityResult.wifi],
        ).isOnline,
        isTrue,
      );
      expect(
        await ConnectivityMonitor(
          check: () async => [ConnectivityResult.none],
        ).isOnline,
        isFalse,
      );
    });

    test('onChanged maps link changes to booleans and drops repeats', () async {
      final controller = StreamController<List<ConnectivityResult>>();
      addTearDown(controller.close);
      final monitor = ConnectivityMonitor(
        changes: controller.stream,
        check: () async => const [ConnectivityResult.none],
      );
      final seen = <bool>[];
      final subscription = monitor.onChanged.listen(seen.add);
      addTearDown(subscription.cancel);

      controller
        ..add([ConnectivityResult.wifi])
        ..add([ConnectivityResult.wifi])
        ..add([ConnectivityResult.none])
        ..add([ConnectivityResult.mobile]);
      await Future<void>.delayed(Duration.zero);

      expect(seen, [true, false, true]);
    });
  });
}

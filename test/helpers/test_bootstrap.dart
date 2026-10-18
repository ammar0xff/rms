import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/core/config/firebase_config.dart';
import 'package:rms/src/core/di/app_bootstrap.dart';
import 'package:rms/src/core/di/app_services.dart';
import 'package:rms/src/core/state/sync_monitor.dart';
import 'package:rms/src/data/local/local_database.dart';
import 'package:rms/src/domain/models/app_role.dart';
import 'package:rms/src/features/shift/shift_screen.dart';

import 'package:sembast/sembast.dart';

int _testDbCounter = 0;

/// Creates an isolated in-memory [AppServices] container for widget & integration tests.
Future<AppServices> createTestServices({
  WidgetTester? tester,
  AppRole initialRole = AppRole.cashier,
  String? email,
}) async {
  Future<AppServices> init() async {
    disableSembastCooperator();
    SyncMonitor.enablePolling = false;
    SyncMonitor.enableConnectivity = false;
    ShiftScreen.enableTicker = false;
    final dbName = 'test_mem_db_${++_testDbCounter}_${DateTime.now().microsecondsSinceEpoch}';
    final db = await LocalDatabase.memory(dbName);
    final services = await bootstrapApp(
      testDatabase: db,
      testConfig: const FirebaseConfig.empty(),
    );

    final userEmail = email ?? switch (initialRole) {
      AppRole.cashier => 'cashier.ahmed@pie.eg',
      AppRole.driver => 'driver.tarek@pie.eg',
      AppRole.manager => 'manager.sara@pie.eg',
      AppRole.developer => 'dev@pie.eg',
    };

    await services.auth.signInWithEmail(email: userEmail, password: 'demo1234');
    return services;
  }

  if (tester != null) {
    AppServices? result;
    await tester.runAsync(() async {
      result = await init();
    });
    return result!;
  }
  return init();
}

extension WidgetTesterExt on WidgetTester {
  void setDesktopSize() {
    view.physicalSize = const Size(1280, 800);
    view.devicePixelRatio = 1.0;
  }

  void setMobileSize() {
    view.physicalSize = const Size(400, 850);
    view.devicePixelRatio = 1.0;
  }

  void resetTestSize() {
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  }

  Future<void> pumpFewFrames([Duration duration = const Duration(milliseconds: 100), int count = 10]) async {
    for (var i = 0; i < count; i++) {
      await pump(duration);
    }
  }
}

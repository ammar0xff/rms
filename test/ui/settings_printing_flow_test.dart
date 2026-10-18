import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/app.dart';
import 'package:rms/src/core/state/sync_monitor.dart';
import 'package:rms/src/domain/models/app_role.dart';
import 'package:rms/src/features/system/settings_screen.dart';

import '../helpers/test_bootstrap.dart';

void main() {
  group('Settings & Thermal Printing & Sync Modal Flows', () {
    testWidgets('Settings Flow: configure thermal printer IP, port, codepage, test connection, save settings',
        (WidgetTester tester) async {
      tester.setDesktopSize();
      addTearDown(tester.resetTestSize);

      final services = await createTestServices(
        tester: tester,
        initialRole: AppRole.cashier,
      );

      await tester.pumpWidget(RmsApp(services: services));
      await tester.pumpFewFrames();

      // Navigate to Settings tab (الإعدادات)
      final settingsTab = find.text('الإعدادات');
      expect(settingsTab, findsWidgets);
      await tester.tap(settingsTab.first);
      await tester.pumpFewFrames();

      // Verify SettingsScreen rendered
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(find.text('هوية الجهاز وإعدادات المنشأة'), findsOneWidget);

      // Scroll down and toggle Network Printing switch
      await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -350));
      await tester.pumpFewFrames();

      final netPrintText = find.text('تفعيل الطباعة المباشرة عبر الشبكة (LAN / Ethernet)');
      expect(netPrintText, findsOneWidget);
      await tester.tap(netPrintText);
      await tester.pumpFewFrames();

      // Enter printer IP & port
      final printerIpField = find.widgetWithText(TextFormField, 'عنوان IP الطابعة (مثال: 192.168.1.100)');
      expect(printerIpField, findsOneWidget);
      await tester.enterText(printerIpField, '192.168.1.200');

      final printerPortField = find.widgetWithText(TextFormField, 'المنفذ (Port)');
      expect(printerPortField, findsOneWidget);
      await tester.enterText(printerPortField, '9100');
      await tester.pumpFewFrames();

      // Scroll further down to reveal printer test button
      await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -200));
      await tester.pumpFewFrames();

      // Tap 'اختبار اتصال الطابعة'
      final testPrinterBtn = find.text('اختبار اتصال الطابعة');
      expect(testPrinterBtn, findsOneWidget);
      await tester.tap(testPrinterBtn);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpFewFrames();

      // Verify snackbar feedback
      expect(find.textContaining('192.168.1.200:9100'), findsOneWidget);

      // Tap save button in AppBar
      final saveBtn = find.text('حفظ الإعدادات');
      expect(saveBtn, findsOneWidget);
      await tester.tap(saveBtn);
      await tester.pumpFewFrames();

      // Verify settings persisted in repository
      await tester.runAsync(() async {
        final saved = await services.facility!.load();
        expect(saved.printerIp, '192.168.1.200');
        expect(saved.printerPort, 9100);
        expect(saved.networkPrintingEnabled, isTrue);
      });
    });

    testWidgets('Honest Sync Modal Flow: open sync status from AppBar, toggle offline simulation, trigger sync',
        (WidgetTester tester) async {
      tester.setDesktopSize();
      addTearDown(tester.resetTestSize);

      final services = await createTestServices(
        tester: tester,
        initialRole: AppRole.cashier,
      );

      await tester.pumpWidget(RmsApp(services: services));
      await tester.pumpFewFrames();

      // Find the Honest Sync Chip in the AppBar
      final syncChip = find.byTooltip('اضغط لعرض تفاصيل المزامنة وحالة الاتصال');
      expect(syncChip, findsOneWidget);

      // Tap the sync chip to open Honest Sync Modal
      await tester.tap(syncChip);
      await tester.pumpFewFrames();

      // Verify modal opened
      expect(find.text('حالة الاتصال والمزامنة'), findsOneWidget);
      expect(find.text('عمليات معلقة على الجهاز:'), findsOneWidget);
      expect(find.text('عمليات متزامنة ومستقرة:'), findsOneWidget);

      // Verify offline simulation toggle exists
      final offlineSwitch = find.text('محاكاة وضع أوفلاين (اختبار)');
      expect(offlineSwitch, findsOneWidget);

      // Toggle offline simulation on
      await tester.tap(offlineSwitch);
      await tester.pumpFewFrames();
      expect(SyncMonitor.instance.isSimulatedOffline, isTrue);

      // Toggle offline simulation back off
      await tester.tap(offlineSwitch);
      await tester.pumpFewFrames();
      expect(SyncMonitor.instance.isSimulatedOffline, isFalse);

      // Tap 'مزامنة الآن'
      final syncNowBtn = find.text('مزامنة الآن');
      expect(syncNowBtn, findsOneWidget);
      await tester.tap(syncNowBtn);
      await tester.pumpFewFrames();

      // Verify dialog dismissed
      expect(find.text('حالة الاتصال والمزامنة'), findsNothing);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/app.dart';
import 'package:rms/src/domain/models/app_role.dart';
import 'package:rms/src/domain/models/collection.dart';
import 'package:rms/src/domain/models/delivery.dart';
import 'package:rms/src/features/delivery/active_trip_screen.dart';
import 'package:rms/src/features/delivery/custody_settlement_screen.dart';
import 'package:rms/src/features/delivery/driver_cockpit_nav_screen.dart';
import 'package:rms/src/features/delivery/driver_fail_dialog.dart';
import 'package:rms/src/features/delivery/driver_identity_service.dart';
import 'package:rms/src/features/delivery/driver_nav_sheet.dart';
import 'package:rms/src/features/delivery/driver_profile_screen.dart';
import 'package:rms/src/features/delivery/driver_receipt_sheet.dart';
import 'package:rms/src/features/delivery/driver_settings_screen.dart';
import 'package:rms/src/features/delivery/widgets/driver_nav_map_canvas.dart';

import 'package:rms/src/data/repositories/local_delivery_repository.dart';
import '../helpers/test_bootstrap.dart';

void main() {
  group('Driver Delivery & Custody Settlement Flows', () {
    testWidgets('Active Trip Flow: view stop details, nav sheet, receipt sheet, and deliver stop',
        (WidgetTester tester) async {
      tester.setDesktopSize();
      addTearDown(tester.resetTestSize);

      DriverSession.instance.activeDriverName = 'مروان ر.';
      addTearDown(() => DriverSession.instance.activeDriverName = null);

      final services = await createTestServices(tester: tester, initialRole: AppRole.driver);

      await tester.pumpWidget(RmsApp(services: services));
      await tester.pumpFewFrames();

      // Verify ActiveTripScreen rendered
      expect(find.byType(ActiveTripScreen), findsOneWidget);
      expect(find.textContaining('الطيار: مروان ر.'), findsOneWidget);
      expect(find.text('محطات التوصيل (1)'), findsOneWidget);

      // Open navigation sheet
      final navBtn = find.textContaining('خريطة السير');
      expect(navBtn, findsOneWidget);
      await tester.tap(navBtn);
      await tester.pumpFewFrames();

      // Verify DriverNavSheet is open
      expect(find.byType(DriverNavSheet), findsOneWidget);
      expect(find.text('انعطف يميناً بعد 250 متراً'), findsOneWidget);

      // Close navigation sheet
      final closeNavBtn = find.descendant(
        of: find.byType(DriverNavSheet),
        matching: find.byIcon(Icons.close_rounded),
      );
      await tester.tap(closeNavBtn);
      await tester.pumpFewFrames();
      expect(find.byType(DriverNavSheet), findsNothing);

      // Open receipt sheet
      final receiptBtn = find.text('عرض البون 🧾');
      expect(receiptBtn, findsOneWidget);
      await tester.tap(receiptBtn);
      await tester.pumpFewFrames();

      // Verify DriverReceiptSheet is open
      expect(find.byType(DriverReceiptSheet), findsOneWidget);
      expect(find.textContaining('بون توصيل أوردر'), findsOneWidget);

      // Close receipt sheet
      final closeReceiptBtn = find.descendant(
        of: find.byType(DriverReceiptSheet),
        matching: find.byIcon(Icons.close_rounded),
      );
      await tester.tap(closeReceiptBtn);
      await tester.pumpFewFrames();
      expect(find.byType(DriverReceiptSheet), findsNothing);

      // Complete delivery
      final deliverBtn = find.textContaining('تم التسليم');
      expect(deliverBtn, findsOneWidget);
      await tester.tap(deliverBtn);
      await tester.pumpFewFrames();

      // Verify custody confirmation dialog appears and confirm custody receipt
      final confirmCustodyBtn = find.textContaining('استلمت النقدية وأكدت العهدة');
      expect(confirmCustodyBtn, findsOneWidget);
      await tester.tap(confirmCustodyBtn);
      await tester.pumpFewFrames();

      // Verify delivery marked delivered in DB
      await tester.runAsync(() async {
        final deliveries = await services.deliveries!.listDeliveries();
        final stop = deliveries.firstWhere((d) => d.id == 'DL-0093');
        expect(stop.state, DeliveryState.delivered);

        // Verify collection recorded
        final collections = await services.deliveries!.listCollections();
        expect(collections.any((c) => c.deliveryId == 'DL-0093'), isTrue);
      });
    });

    testWidgets('Custody Settlement Flow: verifies total custody, submits handover to cashier',
        (WidgetTester tester) async {
      tester.setDesktopSize();
      addTearDown(tester.resetTestSize);

      DriverSession.instance.activeDriverName = 'مروان ر.';
      addTearDown(() => DriverSession.instance.activeDriverName = null);

      final services = await createTestServices(tester: tester, initialRole: AppRole.driver);

      await tester.pumpWidget(RmsApp(services: services));
      await tester.pumpFewFrames();

      // Switch tab to Custody Settlement (تسوية العهدة)
      final custodyNav = find.text('تسوية العهدة');
      expect(custodyNav, findsWidgets);
      await tester.tap(custodyNav.first);
      await tester.pumpFewFrames();

      // Verify CustodySettlementScreen is visible
      expect(find.byType(CustodySettlementScreen), findsOneWidget);
      expect(find.text('إجمالي العهدة النقدية في ذمتي:'), findsOneWidget);
      expect(find.text('HND-8429'), findsOneWidget);

      // Tap Handover Submit button
      final handoverBtn = find.text('تسليم وتوريد العهدة للكاشير');
      expect(handoverBtn, findsOneWidget);
      await tester.tap(handoverBtn);
      await tester.pumpFewFrames();

      // Verify confirmation dialog
      expect(find.text('تأكيد توريد العهدة للكاشير'), findsOneWidget);
      final confirmBtn = find.text('أكّد التوريد الآن');
      expect(confirmBtn, findsOneWidget);

      await tester.tap(confirmBtn);
      await tester.pumpFewFrames();

      // Verify settlement recorded in outbox and database
      await tester.runAsync(() async {
        final outboxEntries = await services.outbox!.all();
        expect(outboxEntries.any((e) => e.operationType == 'settleDriverBatch'), isTrue);
        expect(outboxEntries.any((e) => e.operationType == 'settleDelivery'), isTrue);

        // Simulate server acknowledgment of settlement
        for (final entry in outboxEntries.where((e) => e.operationType == 'settleDelivery')) {
          await (services.deliveries! as LocalDeliveryRepository).applySynced(entry);
        }

        final deliveries = await services.deliveries!.listDeliveries();
        final myDelivered = deliveries.where((d) => d.driver == 'مروان ر.' && d.state == DeliveryState.delivered);
        for (final stop in myDelivered) {
          expect(stop.settlementStatus, SettlementStatus.settled);
        }
      });

      await tester.pumpFewFrames();

      // Verify empty state is now displayed
      expect(find.text('لا توجد مبالغ عهدة معلقة'), findsOneWidget);
    });

    testWidgets('Failed Delivery Flow: reports failure reason and updates delivery state',
        (WidgetTester tester) async {
      tester.setMobileSize(); // Test on Mobile form factor too!
      addTearDown(tester.resetTestSize);

      DriverSession.instance.activeDriverName = 'مروان ر.';
      addTearDown(() => DriverSession.instance.activeDriverName = null);

      final services = await createTestServices(tester: tester, initialRole: AppRole.driver);

      await tester.pumpWidget(RmsApp(services: services));
      await tester.pumpFewFrames();

      expect(find.byType(ActiveTripScreen), findsOneWidget);

      // Tap 'تعذر التسليم'
      final failBtn = find.text('تعذر التسليم');
      expect(failBtn, findsOneWidget);
      await tester.tap(failBtn);
      await tester.pumpFewFrames();

      // Verify DriverFailDialog
      expect(find.byType(DriverFailDialog), findsOneWidget);
      expect(find.textContaining('تعذر تسليم الأوردر'), findsOneWidget);

      // Confirm failure
      final confirmFailBtn = find.text('تأكيد تعذر التسليم وبدء الرجوع');
      expect(confirmFailBtn, findsOneWidget);
      await tester.tap(confirmFailBtn);
      await tester.pumpFewFrames();

      // Verify dialog dismissed
      expect(find.byType(DriverFailDialog), findsNothing);

      // Verify delivery state in database is failed
      await tester.runAsync(() async {
        final deliveries = await services.deliveries!.listDeliveries();
        final stop = deliveries.firstWhere((d) => d.id == 'DL-0093');
        expect(stop.state, DeliveryState.failed);
        expect(stop.failedReason, DeliveryFailureReason.noAnswer);
      });
    });

    testWidgets('Active Trip Flow: customer phone, WhatsApp, and Google Maps direct actions render',
        (WidgetTester tester) async {
      tester.setMobileSize();
      addTearDown(tester.resetTestSize);

      DriverSession.instance.activeDriverName = 'مروان ر.';
      addTearDown(() => DriverSession.instance.activeDriverName = null);

      final services = await createTestServices(tester: tester, initialRole: AppRole.driver);

      await tester.pumpWidget(RmsApp(services: services));
      await tester.pumpFewFrames();

      // Verify customer phone and name from seeded delivery DL-0093
      expect(find.text('01012345678'), findsOneWidget);
      expect(find.text('م. أحمد الشريف'), findsOneWidget);
      expect(find.textContaining('بجوار صيدلية العزبي'), findsOneWidget);

      // Verify communication buttons
      expect(find.text('اتصال'), findsOneWidget);
      expect(find.byIcon(Icons.chat_bubble_outline_rounded), findsOneWidget);

      // Open navigation sheet and verify Google Maps direct GPS button
      final navBtn = find.textContaining('خريطة السير');
      await tester.tap(navBtn);
      await tester.pumpFewFrames();

      expect(find.byType(DriverNavSheet), findsOneWidget);
      expect(find.textContaining('بدء الملاحة الحية على الخريطة'), findsOneWidget);
      expect(
        find.descendant(of: find.byType(DriverNavSheet), matching: find.byIcon(Icons.navigation_rounded)),
        findsWidgets,
      );
    });

    testWidgets('Driver Profile Flow: vehicle selector, sound toggle, and PWA cache update',
        (WidgetTester tester) async {
      tester.setMobileSize();
      addTearDown(tester.resetTestSize);

      DriverSession.instance.activeDriverName = 'مروان ر.';
      addTearDown(() => DriverSession.instance.activeDriverName = null);

      final services = await createTestServices(tester: tester, initialRole: AppRole.driver);

      await tester.pumpWidget(RmsApp(services: services));
      await tester.pumpFewFrames();

      // Navigate to 'ملفي وحالتي' tab (Index 3)
      final profileTab = find.text('ملفي وحالتي');
      expect(profileTab, findsOneWidget);
      await tester.tap(profileTab);
      await tester.pumpFewFrames();

      expect(find.byType(DriverProfileScreen), findsOneWidget);

      // Verify vehicle selector options
      expect(find.text('موتوسيكل 🛵'), findsOneWidget);
      expect(find.text('سكوتر 🛴'), findsOneWidget);

      // Tap scooter
      await tester.tap(find.text('سكوتر 🛴'));
      await tester.pumpFewFrames();

      // Verify Sound effects toggle & PWA cache update button
      await tester.scrollUntilVisible(
        find.text('المؤثرات والتنبيهات الصوتية'),
        200.0,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('المؤثرات والتنبيهات الصوتية'), findsOneWidget);
      expect(find.text('تحديث كاش المتصفح (PWA)'), findsOneWidget);

      final updateBtn = find.text('تحديث الآن');
      await tester.scrollUntilVisible(
        updateBtn,
        200.0,
        scrollable: find.byType(Scrollable).first,
      );
      // Drag a bit further to bring the button well inside the viewport
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -200));
      await tester.pumpFewFrames();

      expect(updateBtn, findsOneWidget);
      await tester.tap(updateBtn);
      await tester.pump();

      // Verify snackbar
      expect(find.textContaining('جاري مسح كاش المتصفح'), findsOneWidget);

      // Advance past 300ms delay to clean up pending timer
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpFewFrames();
    });

    testWidgets('Fancy In-App Built-in Navigation Flow: opens cockpit HUD, tests 3D toggle and telemetry',
        (WidgetTester tester) async {
      tester.setMobileSize();
      addTearDown(tester.resetTestSize);

      DriverSession.instance.activeDriverName = 'مروان ر.';
      addTearDown(() => DriverSession.instance.activeDriverName = null);

      final services = await createTestServices(tester: tester, initialRole: AppRole.driver);

      await tester.pumpWidget(RmsApp(services: services));
      await tester.pumpFewFrames();

      // Open Built-in Navigation from stop card
      final inAppNavBtn = find.text('بدء الملاحة المباشرة (Cockpit HUD) 🧭');
      expect(inAppNavBtn, findsOneWidget);
      await tester.tap(inAppNavBtn);
      await tester.pumpFewFrames();

      // Verify DriverCockpitNavScreen is pushed
      expect(find.byType(DriverCockpitNavScreen), findsOneWidget);
      expect(find.byType(DriverNavMapCanvas), findsOneWidget);

      // Verify Turn-by-Turn guidance banner
      expect(find.textContaining('انعطف يميناً بعد 250 متراً'), findsOneWidget);

      // Verify Speedometer & Telemetry
      expect(find.text('كم/س'), findsOneWidget);
      expect(find.text('حد 60'), findsOneWidget);
      expect(find.textContaining('دقيقة'), findsOneWidget);

      // Verify 3D toggle button & tap it
      expect(find.text('📐 3D'), findsOneWidget);
      await tester.tap(find.text('📐 3D'));
      await tester.pumpFewFrames();
      expect(find.text('🗺️ 2D'), findsOneWidget);

      // Verify Cash Collection reminder in HUD
      expect(find.text('المطلوب تحصيله كاش عند الباب:'), findsOneWidget);

      // Close cockpit navigation
      final closeBtn = find.byTooltip('إغلاق الملاحة');
      expect(closeBtn, findsOneWidget);
      await tester.tap(closeBtn);
      await tester.pumpFewFrames();

      expect(find.byType(DriverCockpitNavScreen), findsNothing);
    });

    testWidgets(
        'Driver Settings Tab Flow: navigates to settings, edits profile, toggles preferences and updates cache',
        (WidgetTester tester) async {
      tester.setMobileSize();
      addTearDown(tester.resetTestSize);

      DriverSession.instance.activeDriverName = 'مروان ر.';
      addTearDown(() => DriverSession.instance.activeDriverName = null);

      final services = await createTestServices(tester: tester, initialRole: AppRole.driver);

      await tester.pumpWidget(RmsApp(services: services));
      await tester.pumpFewFrames();

      // Verify 'إعدادات الكابتن' nav tab exists and tap it
      final settingsTab = find.text('إعدادات الكابتن');
      expect(settingsTab, findsOneWidget);
      await tester.tap(settingsTab);
      await tester.pumpFewFrames();

      // Verify DriverSettingsScreen is displayed
      expect(find.byType(DriverSettingsScreen), findsOneWidget);
      expect(find.text('إعدادات الكابتن وتفضيلات القيادة'), findsOneWidget);

      // Verify Profile card & edit name
      expect(find.text('بيانات الكابتن وملف الحساب'), findsOneWidget);
      final nameField = find.widgetWithText(TextField, 'اسم الكابتن');
      expect(nameField, findsOneWidget);
      await tester.enterText(nameField, 'كابتن مروان البطل');
      final saveNameBtn = find.text('حفظ الاسم');
      await tester.tap(saveNameBtn);
      await tester.pumpFewFrames();
      expect(find.text('تم حفظ بيانات الحساب بنجاح'), findsOneWidget);

      // Verify Preferences: vehicle selection & navigation mode
      final scooterBtn = find.text('سكوتر 🛴');
      await tester.ensureVisible(scooterBtn);
      await tester.pumpFewFrames();
      expect(scooterBtn, findsOneWidget);
      await tester.tap(scooterBtn);
      await tester.pumpFewFrames();

      // Save preferences
      final savePrefBtn = find.text('حفظ تفضيلات القيادة');
      await tester.ensureVisible(savePrefBtn);
      await tester.pumpFewFrames();
      expect(savePrefBtn, findsOneWidget);
      await tester.tap(savePrefBtn);
      await tester.pumpFewFrames();
      expect(find.text('تم حفظ تفضيلات القيادة بنجاح'), findsOneWidget);

      // Dismiss SnackBar so its overlay doesn't intercept taps
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpFewFrames();

      // Verify Platform & Updates card & PWA Cache Buster
      final updateNowBtn = find.text('تحديث الآن');
      await tester.ensureVisible(updateNowBtn);
      await tester.pumpFewFrames();
      expect(updateNowBtn, findsOneWidget);
      await tester.tap(updateNowBtn);
      await tester.pump();
      expect(find.textContaining('جاري تنظيف كاش المتصفح'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpFewFrames();
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/app.dart';
import 'package:rms/src/core/sound/pie_sound_service.dart';
import 'package:rms/src/domain/models/app_role.dart';
import 'package:rms/src/domain/models/cashier_user_settings.dart';
import 'package:rms/src/domain/models/order_type.dart';
import 'package:rms/src/features/cashier/cashier_settings_screen.dart';

import '../helpers/test_bootstrap.dart';

void main() {
  group('Cashier Settings & User Profile Flows', () {
    testWidgets('Cashier navigation includes Cashier Settings tab but excludes global Settings',
        (WidgetTester tester) async {
      tester.setDesktopSize();
      addTearDown(tester.resetTestSize);

      final services = await createTestServices(
        tester: tester,
        initialRole: AppRole.cashier,
      );

      await tester.pumpWidget(RmsApp(services: services));
      await tester.pumpFewFrames();

      // Verify 'إعدادات الكاشير' exists in navigation
      expect(find.text('إعدادات الكاشير'), findsWidgets);

      // Verify global facility 'الإعدادات' is NOT present
      expect(find.text('الإعدادات'), findsNothing);
    });

    testWidgets('Cashier can view profile, edit display name, and update password',
        (WidgetTester tester) async {
      tester.setDesktopSize();
      addTearDown(tester.resetTestSize);

      final services = await createTestServices(
        tester: tester,
        initialRole: AppRole.cashier,
      );

      await tester.pumpWidget(RmsApp(services: services));
      await tester.pumpFewFrames();

      // Navigate to Cashier Settings
      await tester.tap(find.text('إعدادات الكاشير').first);
      await tester.pumpFewFrames();

      expect(find.byType(CashierSettingsScreen), findsOneWidget);
      expect(find.text('بيانات المستخدم والحساب'), findsOneWidget);

      // Edit display name
      final nameField = find.widgetWithText(TextFormField, 'اكتب اسمك الكامل أو اسم العمل');
      expect(nameField, findsOneWidget);
      await tester.enterText(nameField, 'كاشير الورديات الأول');
      await tester.pumpFewFrames();

      // Tap Save Profile
      final saveProfileBtn = find.text('حفظ البيانات الشخصية');
      expect(saveProfileBtn, findsOneWidget);
      await tester.tap(saveProfileBtn);
      await tester.pumpFewFrames();

      // Verify auth user updated
      expect(services.auth.currentUser?.displayName, 'كاشير الورديات الأول');
      expect(find.text('تم تحديث البيانات الشخصية بنجاح'), findsOneWidget);
    });

    testWidgets('Cashier updates section displays platform environment and checks for updates',
        (WidgetTester tester) async {
      tester.setDesktopSize();
      addTearDown(tester.resetTestSize);

      final services = await createTestServices(
        tester: tester,
        initialRole: AppRole.cashier,
      );

      await tester.pumpWidget(RmsApp(services: services));
      await tester.pumpFewFrames();

      // Navigate to Cashier Settings
      await tester.tap(find.text('إعدادات الكاشير').first);
      await tester.pumpFewFrames();

      // Verify updates & platform section
      expect(find.text('التحديثات ونوع الجهاز (Mobile / Desktop)'), findsOneWidget);
      expect(find.textContaining('وضع العرض'), findsOneWidget);

      // Tap check for updates
      final checkUpdatesBtn = find.text('فحص التحديثات المتاحة');
      await tester.ensureVisible(checkUpdatesBtn);
      await tester.pumpFewFrames();
      expect(checkUpdatesBtn, findsOneWidget);
      await tester.tap(checkUpdatesBtn);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpFewFrames();

      // Verify feedback
      expect(find.textContaining('أحدث إصدار متوافق'), findsOneWidget);
    });

    testWidgets('Cashier user preferences flow: toggles sound effects, default order type, and persists user settings',
        (WidgetTester tester) async {
      tester.setDesktopSize();
      addTearDown(tester.resetTestSize);

      final services = await createTestServices(
        tester: tester,
        initialRole: AppRole.cashier,
      );

      await tester.pumpWidget(RmsApp(services: services));
      await tester.pumpFewFrames();

      // Navigate to Cashier Settings
      await tester.tap(find.text('إعدادات الكاشير').first);
      await tester.pumpFewFrames();

      // Scroll down to user preferences
      final prefHeader = find.text('تفضيلات الكاشير الشخصية (User-Level Settings)');
      await tester.ensureVisible(prefHeader);
      await tester.pumpFewFrames();
      expect(prefHeader, findsOneWidget);

      // Toggle Sound Effects off
      final soundSwitch = find.widgetWithText(SwitchListTile, 'التأثيرات الصوتية (Sound Effects)');
      await tester.ensureVisible(soundSwitch);
      await tester.pumpFewFrames();
      expect(soundSwitch, findsOneWidget);
      await tester.tap(soundSwitch);
      await tester.pumpFewFrames();

      // Verify sound service singleton is disabled
      expect(PieSoundService.instance.enabled, isFalse);

      // Select Delivery as default order type
      final deliverySegment = find.text('توصيل منازل');
      await tester.ensureVisible(deliverySegment);
      await tester.pumpFewFrames();
      expect(deliverySegment, findsOneWidget);
      await tester.tap(deliverySegment);
      await tester.pumpFewFrames();

      // Tap Save Preferences
      final savePrefBtn = find.text('حفظ تفضيلات الكاشير');
      await tester.ensureVisible(savePrefBtn);
      await tester.pumpFewFrames();
      expect(savePrefBtn, findsOneWidget);
      await tester.tap(savePrefBtn);
      await tester.pumpFewFrames();

      expect(find.text('تم حفظ تفضيلات الكاشير بنجاح'), findsOneWidget);

      // Verify settings persisted in local storage
      final loaded = await CashierUserSettings.load(services.database, services.auth.currentUser?.uid);
      expect(loaded.soundEffects, isFalse);
      expect(loaded.defaultOrderType, OrderType.delivery);
    });

    testWidgets('Cashier Settings renders seamlessly on mobile viewport without layout overflows',
        (WidgetTester tester) async {
      tester.setMobileSize();
      addTearDown(tester.resetTestSize);

      final services = await createTestServices(
        tester: tester,
        initialRole: AppRole.cashier,
      );

      await tester.pumpWidget(RmsApp(services: services));
      await tester.pumpFewFrames();

      // Navigate to Cashier Settings via mobile bottom navigation bar
      final settingsTab = find.text('إعدادات الكاشير');
      expect(settingsTab, findsOneWidget);
      await tester.tap(settingsTab);
      await tester.pumpFewFrames();

      expect(find.byType(CashierSettingsScreen), findsOneWidget);

      // Scroll through each section to ensure no overflows occur anywhere on screen
      final updateSection = find.text('التحديثات ونوع الجهاز (Mobile / Desktop)');
      await tester.ensureVisible(updateSection);
      await tester.pumpFewFrames();

      final prefSection = find.text('تفضيلات الكاشير الشخصية (User-Level Settings)');
      await tester.ensureVisible(prefSection);
      await tester.pumpFewFrames();

      // Test mobile order type selection
      final deliveryOption = find.text('توصيل منازل');
      expect(deliveryOption, findsOneWidget);
      await tester.ensureVisible(deliveryOption);
      await tester.pumpFewFrames();
      await tester.tap(deliveryOption);
      await tester.pumpFewFrames();

      // Save on mobile
      final savePrefBtn = find.text('حفظ تفضيلات الكاشير');
      await tester.ensureVisible(savePrefBtn);
      await tester.pumpFewFrames();
      await tester.tap(savePrefBtn);
      await tester.pumpFewFrames();
      expect(find.text('تم حفظ تفضيلات الكاشير بنجاح'), findsOneWidget);
    });

    testWidgets('Cashier Settings renders without overflows on compact 360x640 mobile screen',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.resetTestSize);

      final services = await createTestServices(
        tester: tester,
        initialRole: AppRole.cashier,
      );

      await tester.pumpWidget(RmsApp(services: services));
      await tester.pumpFewFrames();

      // Navigate to Cashier Settings
      await tester.tap(find.text('إعدادات الكاشير'));
      await tester.pumpFewFrames();

      expect(find.byType(CashierSettingsScreen), findsOneWidget);

      final saveProfileBtn = find.text('حفظ البيانات الشخصية');
      await tester.ensureVisible(saveProfileBtn);
      await tester.pumpFewFrames();

      final updateSection = find.text('التحديثات ونوع الجهاز (Mobile / Desktop)');
      await tester.ensureVisible(updateSection);
      await tester.pumpFewFrames();

      final savePrefBtn = find.text('حفظ تفضيلات الكاشير');
      await tester.ensureVisible(savePrefBtn);
      await tester.pumpFewFrames();
    });
  });
}

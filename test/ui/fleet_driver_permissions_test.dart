import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/app.dart';
import 'package:rms/src/core/di/app_services.dart';
import 'package:rms/src/domain/models/app_role.dart';
import 'package:rms/src/features/delivery/fleet_screen.dart';
import 'package:rms/src/features/manager/team_screen.dart';

import '../helpers/test_bootstrap.dart';

void main() {
  group('Fleet Driver Permissions & Role Gating', () {
    testWidgets('Cashier cannot create drivers in FleetScreen and sees manager referral empty state',
        (WidgetTester tester) async {
      tester.setDesktopSize();
      addTearDown(tester.resetTestSize);

      final services = await createTestServices(
        tester: tester,
        initialRole: AppRole.cashier,
      );

      // Ensure drivers store is empty (production baseline)
      await tester.runAsync(() async {
        await services.deliveries?.cacheDrivers([], replace: true);
      });

      await tester.pumpWidget(RmsApp(services: services));
      await tester.pumpFewFrames();

      // Navigate to FleetScreen (طيارين الفرع)
      final fleetTab = find.text('طيارين الفرع');
      expect(fleetTab, findsWidgets);
      await tester.tap(fleetTab.first);
      await tester.pumpFewFrames();

      // Verify FleetScreen is displayed
      expect(find.byType(FleetScreen), findsOneWidget);

      // Verify cashier CANNOT see 'إضافة كابتن توصيل' button or 'إضافة كابتن' button
      expect(find.text('إضافة كابتن توصيل'), findsNothing);
      expect(find.text('إضافة كابتن'), findsNothing);

      // Verify cashier-tailored empty state directing to branch manager
      expect(find.text('مفيش طيارين متسجلين في الفرع'), findsOneWidget);
      expect(
        find.text('لم يقم مدير الفرع بإضافة كباتن توصيل بعد. يرجى مراجعة إدارة الفرع لتسجيل طياري الفرع.'),
        findsOneWidget,
      );
    });

    testWidgets('Manager can register driver via TeamScreen and driver is synced to fleet',
        (WidgetTester tester) async {
      tester.setDesktopSize();
      addTearDown(tester.resetTestSize);

      final services = await createTestServices(
        tester: tester,
        initialRole: AppRole.manager,
      );

      // Clear drivers repository
      await tester.runAsync(() async {
        await services.deliveries?.cacheDrivers([], replace: true);
      });

      await tester.pumpWidget(RmsApp(services: services));
      await tester.pumpFewFrames();

      // Navigate to TeamScreen (فريق العمل)
      final teamTab = find.text('فريق العمل');
      expect(teamTab, findsWidgets);
      await tester.tap(teamTab.first);
      await tester.pumpFewFrames();

      expect(find.byType(TeamScreen), findsOneWidget);

      // Tap 'إضافة موظف'
      final addMemberBtn = find.text('إضافة موظف');
      expect(addMemberBtn, findsOneWidget);
      await tester.tap(addMemberBtn);
      await tester.pumpFewFrames();

      // Dialog opens
      expect(find.text('إضافة موظف جديد للفريق'), findsOneWidget);

      // Enter name & email
      final textFields = find.byType(TextField);
      await tester.enterText(textFields.at(0), 'كابتن وليد سليم');
      await tester.enterText(textFields.at(1), 'waleed.driver@pie.eg');

      // Select driver role chip (طيار) inside dialog
      final driverChip = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('طيار'),
      );
      expect(driverChip, findsOneWidget);
      await tester.tap(driverChip);
      await tester.pumpFewFrames();

      // Tap 'حفظ الموظف'
      final saveBtn = find.text('حفظ الموظف');
      expect(saveBtn, findsOneWidget);
      await tester.tap(saveBtn);
      await tester.pumpFewFrames();

      // Verify driver is saved into delivery repo
      await tester.runAsync(() async {
        final drivers = await services.deliveries?.listDrivers() ?? [];
        expect(drivers.any((d) => d.name == 'كابتن وليد سليم'), isTrue);
      });
    });

    testWidgets('FleetScreen with privileged manager shows add driver controls',
        (WidgetTester tester) async {
      tester.setDesktopSize();
      addTearDown(tester.resetTestSize);

      final services = await createTestServices(
        tester: tester,
        initialRole: AppRole.manager,
      );

      await tester.runAsync(() async {
        await services.deliveries?.cacheDrivers([], replace: true);
      });

      // Render FleetScreen directly in an AppScope with manager credentials
      await tester.pumpWidget(
        MaterialApp(
          home: AppScope(
            services: services,
            child: const Scaffold(
              body: FleetScreen(),
            ),
          ),
        ),
      );
      await tester.pumpFewFrames();

      // Manager MUST see 'إضافة كابتن توصيل' button
      expect(find.text('إضافة كابتن توصيل'), findsOneWidget);
      expect(find.text('إضافة كابتن'), findsOneWidget);

      // Manager empty state directs to add button
      expect(
        find.text('اضغط على زر إضافة كابتن بالأعلى لتسجيل وتعيين طياري الفرع.'),
        findsOneWidget,
      );

      // Tap 'إضافة كابتن توصيل'
      await tester.tap(find.text('إضافة كابتن توصيل'));
      await tester.pumpFewFrames();

      // Dialog opens
      expect(find.text('إضافة كابتن توصيل بالفرع'), findsOneWidget);

      // Fill in driver name
      await tester.enterText(find.byType(TextFormField), 'كابتن حسام مصطفى');
      await tester.pumpFewFrames();

      // Save driver
      await tester.tap(find.text('حفظ وإضافة'));
      await tester.pumpFewFrames();

      // Verify driver is now displayed
      expect(find.text('كابتن حسام مصطفى'), findsOneWidget);
      expect(find.text('مفيش طيارين متسجلين في الفرع'), findsNothing);

      // Verify driver saved to repository
      await tester.runAsync(() async {
        final drivers = await services.deliveries?.listDrivers() ?? [];
        expect(drivers.any((d) => d.name == 'كابتن حسام مصطفى'), isTrue);
      });
    });
  });
}

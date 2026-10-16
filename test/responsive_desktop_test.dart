import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/core/config/firebase_config.dart';
import 'package:rms/src/core/di/app_services.dart';
import 'package:rms/src/core/theme/app_theme.dart';
import 'package:rms/src/data/local/outbox/outbox_status.dart';
import 'package:rms/src/data/repositories/demo_auth_repository.dart';
import 'package:rms/src/features/accounting/accounting_screen.dart';
import 'package:rms/src/features/branches/branches_screen.dart';
import 'package:rms/src/features/conflicts/conflicts_screen.dart';
import 'package:rms/src/features/customers/customers_screen.dart';
import 'package:rms/src/features/dashboard/dashboard_screen.dart';
import 'package:rms/src/features/database/database_screen.dart';
import 'package:rms/src/features/delivery/delivery_screen.dart';
import 'package:rms/src/features/delivery/trip_log_screen.dart';
import 'package:rms/src/features/inventory/inventory_screen.dart';
import 'package:rms/src/features/menu/menu_screen.dart';
import 'package:rms/src/features/pos/pos_screen.dart';
import 'package:rms/src/features/purchasing/purchasing_screen.dart';
import 'package:rms/src/features/reports/reports_screen.dart';
import 'package:rms/src/features/settings/settings_screen.dart';
import 'package:rms/src/features/shift/shift_screen.dart';
import 'package:rms/src/features/sync/sync_center_screen.dart';
import 'package:rms/src/features/tables/tables_screen.dart';
import 'package:rms/src/features/system/system_screen.dart';
import 'package:rms/src/features/team/team_screen.dart';

import 'support/app_fakes.dart';

/// The PC proof: every screen at 1440x900, empty and data-filled.
///
/// Wide screens fail differently than phones — stretched heroes, squeezed
/// lanes, side-by-side panels that only exist above 600/700/900px. Each
/// case below renders those paths; overflow fails the test.
Future<void> _pumpDesktopBare(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    AppScope(
      services: AppServices(
        config: const FirebaseConfig.empty(),
        auth: DemoAuthRepository(),
        firebaseReady: false,
      ),
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: screen),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('desktop render sweep (1440x900), empty stores', () {
    testWidgets('shift renders', (t) => _pumpDesktopBare(t, const ShiftScreen()));
    testWidgets('dashboard renders',
        (t) => _pumpDesktopBare(t, const DashboardScreen()));
    testWidgets('pos renders', (t) => _pumpDesktopBare(t, const PosScreen()));
    testWidgets('delivery renders',
        (t) => _pumpDesktopBare(t, const DeliveryScreen()));
    testWidgets('menu renders', (t) => _pumpDesktopBare(t, const MenuScreen()));
    testWidgets('inventory renders',
        (t) => _pumpDesktopBare(t, const InventoryScreen()));
    testWidgets('purchasing renders',
        (t) => _pumpDesktopBare(t, const PurchasingScreen()));
    testWidgets('customers renders',
        (t) => _pumpDesktopBare(t, const CustomersScreen()));
    testWidgets('accounting renders',
        (t) => _pumpDesktopBare(t, const AccountingScreen()));
    testWidgets('reports renders',
        (t) => _pumpDesktopBare(t, const ReportsScreen()));
    testWidgets('branches renders',
        (t) => _pumpDesktopBare(t, const BranchesScreen()));
    testWidgets('system renders',
        (t) => _pumpDesktopBare(t, const SystemScreen()));
    testWidgets('sync center renders',
        (t) => _pumpDesktopBare(t, const SyncCenterScreen()));
    testWidgets('database renders',
        (t) => _pumpDesktopBare(t, const DatabaseScreen()));
    testWidgets('conflicts renders',
        (t) => _pumpDesktopBare(t, const ConflictsScreen()));
    testWidgets('team renders', (t) => _pumpDesktopBare(t, const TeamScreen()));
    testWidgets('tables renders', (t) => _pumpDesktopBare(t, const TablesScreen()));
    testWidgets('trip log renders',
        (t) => _pumpDesktopBare(t, const TripLogScreen()));
    testWidgets('settings renders',
        (t) => _pumpDesktopBare(t, const SettingsScreen()));
  });

  group('desktop with rows (1440x900)', () {
    testWidgets('shift hero sits beside its figure', (tester) async {
      await pumpDesktop(tester, const ShiftScreen());

      expect(find.text('شيفت النهاردة'), findsOneWidget);
      expect(find.text('أحدث الطلبات'), findsOneWidget);
    });

    testWidgets('dashboard panels share the row', (tester) async {
      await pumpDesktop(tester, const DashboardScreen());

      expect(find.textContaining('دجاج متبل بكمية كبيرة للشواء'),
          findsOneWidget);
    });

    testWidgets('pos counter rails filter and tender', (tester) async {
      await pumpDesktop(tester, const PosScreen());

      expect(find.text('مشويات مشكلة كبيرة مع الأرز البسمتي'),
          findsOneWidget);
      // The rail replaces the phone chip strip on wide screens.
      await tester.tap(find.text('البيتزا'));
      await tester.pumpAndSettle();
      expect(find.text('مشويات مشكلة كبيرة مع الأرز البسمتي'),
          findsNothing);
      expect(find.text('بيتزا خضار'), findsOneWidget);
      await tester.tap(find.text('الكل'));
      await tester.pumpAndSettle();
      // Quick tender skips the amount dialog; it renders, never tapped here
      // (tapping submits a real order through the fake).
      await tester.tap(find.text('مشويات مشكلة كبيرة مع الأرز البسمتي'));
      await tester.pumpAndSettle();
      expect(find.text('كاش بالظبط'), findsOneWidget);
      expect(find.text('فيزا'), findsWidgets);
    });

    testWidgets('menu station groups', (tester) async {
      await pumpDesktop(tester, const MenuScreen());

      expect(find.text('المشويات'), findsOneWidget);
      expect(find.text('مشويات مشكلة كبيرة مع الأرز البسمتي'),
          findsOneWidget);
      // Search filters across stations; empty groups hide.
      await tester.enterText(find.byType(TextField), 'بيتزا');
      await tester.pumpAndSettle();
      expect(find.text('المشويات'), findsNothing);
      expect(find.text('بيتزا خضار'), findsOneWidget);
    });

    testWidgets('delivery ops tables', (tester) async {
      await pumpDesktop(tester, const DeliveryScreen());

      expect(find.textContaining('طلب-توصيل-طويل-001'), findsWidgets);
    });

    testWidgets('purchasing tables', (tester) async {
      await pumpDesktop(tester, const PurchasingScreen());

      expect(find.textContaining('PO-2026-1042'), findsOneWidget);
    });

    testWidgets('accounting ledger', (tester) async {
      await pumpDesktop(tester, const AccountingScreen());

      expect(find.textContaining('طلب-توصيل-طويل-001'), findsWidgets);
    });

    testWidgets('reports snapshot', (tester) async {
      await pumpDesktop(tester, const ReportsScreen());

      expect(find.text('اتجاه المبيعات'), findsOneWidget);
    });

    testWidgets('trip log day totals', (tester) async {
      await pumpDesktop(tester, const TripLogScreen());

      expect(find.text('أوردرات خلصانة'), findsOneWidget);
      await tester.tap(find.text('المرتجعات'));
      await tester.pumpAndSettle();
    });

    testWidgets('tables floor with zones', (tester) async {
      await pumpDesktop(tester, const TablesScreen());

      expect(find.text('الصالة'), findsOneWidget);
      expect(find.text('T-01'), findsOneWidget);
    });

    testWidgets('branches cards and detail sheet', (tester) async {
      await pumpDesktop(tester, const BranchesScreen());

      expect(find.text('بوابة الشمال الرئيسية'), findsWidgets);
      // Row tap drills into the read-only detail sheet.
      await tester.tap(find.text('بوابة الشمال الرئيسية').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('NS-01'), findsWidgets);
      expect(find.text('اقفل'), findsOneWidget);
    });

    testWidgets('sync outbox with stuck rows', (tester) async {
      await pumpDesktop(
        tester,
        const SyncCenterScreen(),
        outbox: FakeOutbox([
          fakeOp('a', 'order', 'createOrder', OutboxStatus.pending),
          fakeOp('b', 'payment', 'recordPayment',
              OutboxStatus.retryableFailure,
              error: 'تعذّر الاتصال. تحقق من الشبكة.'),
        ]),
      );

      expect(find.text('op-a'), findsOneWidget);
    });
  });
}

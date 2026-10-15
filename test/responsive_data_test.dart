import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/data/local/outbox/outbox_status.dart';
import 'package:rms/src/features/accounting/accounting_screen.dart';
import 'package:rms/src/features/branches/branches_screen.dart';
import 'package:rms/src/features/conflicts/conflicts_screen.dart';
import 'package:rms/src/features/customers/customers_screen.dart';
import 'package:rms/src/features/dashboard/dashboard_screen.dart';
import 'package:rms/src/features/delivery/delivery_screen.dart';
import 'package:rms/src/features/inventory/inventory_screen.dart';
import 'package:rms/src/features/kitchen/kitchen_screen.dart';
import 'package:rms/src/features/menu/menu_screen.dart';
import 'package:rms/src/features/pos/pos_screen.dart';
import 'package:rms/src/features/purchasing/purchasing_screen.dart';
import 'package:rms/src/features/reports/reports_screen.dart';
import 'package:rms/src/features/shift/shift_screen.dart';
import 'package:rms/src/features/sync/sync_center_screen.dart';

import 'support/app_fakes.dart';

/// Tables and lists WITH rows, at phone width. See support/app_fakes.dart
/// for the shared repositories; this file only holds the cases.
void main() {
  group('tables and lists with rows at 390px', () {
    testWidgets('pos grid, cart badge, and cart row', (tester) async {
      await pumpPhone(tester, const PosScreen());

      expect(find.text(kLongName), findsOneWidget);
      await tester.tap(find.text(kLongName));
      await tester.pumpAndSettle();

      expect(find.text('السلة (1)'), findsOneWidget);
      await tester.tap(find.text('السلة (1)'));
      await tester.pumpAndSettle();

      // The cart holds the line and prices it; both must be on screen.
      expect(find.text(kLongName), findsWidgets);
      expect(find.textContaining('185.50'), findsWidgets);
    });

    testWidgets('kitchen lanes show tickets', (tester) async {
      await pumpPhone(tester, const KitchenScreen());

      expect(find.text('طلب-t1'), findsOneWidget);
      expect(find.text('طلب-t2'), findsOneWidget);
      expect(find.text('طلب-t3'), findsOneWidget);
    });

    testWidgets('delivery jobs, drivers, and collections', (tester) async {
      await pumpPhone(tester, const DeliveryScreen());

      expect(find.textContaining('طلب-توصيل-طويل-001'), findsWidgets);
      expect(find.textContaining('مروان ر.'), findsWidgets);
    });

    testWidgets('menu table shows the long item name', (tester) async {
      await pumpPhone(tester, const MenuScreen());

      expect(find.text(kLongName), findsOneWidget);
    });

    testWidgets('inventory ledger shows items and movements',
        (tester) async {
      await pumpPhone(tester, const InventoryScreen());

      expect(find.textContaining('دجاج متبل بكمية كبيرة للشواء'), findsWidgets);
    });

    testWidgets('customers table shows the long name', (tester) async {
      await pumpPhone(tester, const CustomersScreen());

      expect(find.textContaining('محمد السيد عبد الرحمن الطويل'), findsOneWidget);
    });

    testWidgets('purchasing shows suppliers and orders', (tester) async {
      await pumpPhone(tester, const PurchasingScreen());

      expect(find.textContaining('مورد اللحوم الرئيسي للفرع'), findsWidgets);
      await tester.tap(find.text('الأوامر'));
      await tester.pumpAndSettle();
      expect(find.textContaining('PO-2026-1042'), findsOneWidget);
    });

    testWidgets('accounting shows payments and requests', (tester) async {
      await pumpPhone(tester, const AccountingScreen());

      expect(find.textContaining('طلب-توصيل-طويل-001'), findsWidgets);
    });

    testWidgets('dashboard renders orders, low stock, and rollups',
        (tester) async {
      await pumpPhone(tester, const DashboardScreen());

      expect(find.textContaining('دجاج متبل بكمية كبيرة للشواء'), findsOneWidget);
    });

    testWidgets('reports renders the snapshot, not the unavailable notice',
        (tester) async {
      await pumpPhone(tester, const ReportsScreen());

      expect(find.text('اتجاه المبيعات'), findsOneWidget);
      expect(find.text('التقارير غير متاحة'), findsNothing);
    });

    testWidgets('branches renders the branch card', (tester) async {
      await pumpPhone(tester, const BranchesScreen());

      expect(find.text('بوابة الشمال الرئيسية'), findsWidgets);
      expect(find.text('شبكة الفروع'), findsOneWidget);
    });

    testWidgets('shift renders today\'s order rows', (tester) async {
      await pumpPhone(tester, const ShiftScreen());

      expect(find.text('أحدث الطلبات'), findsOneWidget);
      expect(find.text('طلب-توصيل-طويل-001'), findsOneWidget);
    });

    testWidgets('sync outbox shows stuck rows and their errors',
        (tester) async {
      await pumpPhone(
        tester,
        const SyncCenterScreen(),
        outbox: FakeOutbox([
          fakeOp('a', 'order', 'createOrder', OutboxStatus.pending),
          fakeOp('b', 'payment', 'recordPayment', OutboxStatus.retryableFailure,
              error: 'تعذّر الاتصال. تحقق من الشبكة.'),
          fakeOp('c', 'order', 'createOrder', OutboxStatus.conflict),
        ]),
      );

      expect(find.text('op-a'), findsOneWidget);
      expect(find.textContaining('تعذّر الاتصال. تحقق من الشبكة.'),
          findsOneWidget);
    });

    testWidgets('conflicts list shows entries awaiting resolution',
        (tester) async {
      await pumpPhone(
        tester,
        const ConflictsScreen(),
        outbox: FakeOutbox([
          fakeOp('x', 'payment', 'recordPayment', OutboxStatus.conflict),
          fakeOp('y', 'order', 'createOrder', OutboxStatus.requiresUserAction),
        ]),
      );

      expect(find.text('e-x'), findsOneWidget);
      expect(find.text('e-y'), findsOneWidget);
      expect(find.text('مفيش تعارضات مستنية الحل.'), findsNothing);
    });
  });
}
import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/app.dart';
import 'package:rms/src/data/local/local_stores.dart';
import 'package:rms/src/domain/models/app_role.dart';
import 'package:rms/src/domain/models/order.dart';
import 'package:rms/src/domain/models/order_draft.dart';
import 'package:rms/src/domain/models/order_type.dart';
import 'package:rms/src/features/accounting/invoices_screen.dart';
import 'package:rms/src/features/shift/shift_screen.dart';
import 'package:sembast/sembast.dart';

import '../helpers/test_bootstrap.dart';

void main() {
  group('Shift and Invoices Edge Cases & Visual Stability', () {
    testWidgets('Both ShiftScreen and InvoicesScreen render with zero data without blank screen on mobile', (WidgetTester tester) async {
      tester.setMobileSize();
      addTearDown(tester.resetTestSize);

      final services = await createTestServices(tester: tester, initialRole: AppRole.cashier);

      // Wipe out any seeded sessions or orders to test complete zero state
      await LocalStores.orders.delete(services.database!.db);
      await LocalStores.cashSessions.delete(services.database!.db);

      await tester.pumpWidget(RmsApp(services: services));
      await tester.pumpFewFrames();

      // 1. Navigate to Shift Screen (الوردية والخزينة)
      final shiftNav = find.text('الوردية والخزينة');
      expect(shiftNav, findsWidgets);
      await tester.tap(shiftNav.first);
      await tester.pumpFewFrames();

      expect(find.byType(ShiftScreen), findsOneWidget);
      expect(find.text('الوردية مقفولة'), findsOneWidget);
      expect(find.text('مفيش أوردرات في الشيفت ده لسه'), findsOneWidget);
      expect(find.text('فتح وردية جديدة وتعيين العهدة'), findsOneWidget);

      // 2. Navigate to Invoices Screen (سجل الفواتير)
      final invoiceNav = find.text('سجل الفواتير');
      expect(invoiceNav, findsWidgets);
      await tester.tap(invoiceNav.first);
      await tester.pumpFewFrames();

      expect(find.byType(InvoicesScreen), findsOneWidget);
      expect(find.text('مفيش فواتير مطابقة'), findsOneWidget);
    });

    testWidgets('Both ShiftScreen and InvoicesScreen render cleanly with multiple edge case orders on desktop', (WidgetTester tester) async {
      tester.setDesktopSize();
      addTearDown(tester.resetTestSize);

      final services = await createTestServices(tester: tester, initialRole: AppRole.cashier);

      // Create an order with zero items and an order with full items
      final draft1 = OrderDraft(
        orderType: OrderType.dineIn,
        items: const [],
        taxAmount: 0.0,
        serviceAmount: 0.0,
      );
      final draft2 = OrderDraft(
        orderType: OrderType.delivery,
        items: const [
          OrderItem(
            productId: 'p_edge',
            name: 'فطيرة مشلتت عسل وقشطة',
            unitPrice: 150.0,
            quantity: 3,
            modifiers: ['عسل إضافي', 'قشطة بلدي'],
            note: 'تسوية زيادة ومقرمشة',
          ),
        ],
        taxAmount: 63.0,
        serviceAmount: 15.0,
      );
      final created1 = await services.orders!.createOrder(draft1);
      final created2 = await services.orders!.createOrder(draft2);

      await tester.pumpWidget(RmsApp(services: services));
      await tester.pumpFewFrames();

      // 1. Open Shift Screen
      final shiftNav = find.text('الوردية والخزينة');
      await tester.tap(shiftNav.first);
      await tester.pumpFewFrames();

      expect(find.byType(ShiftScreen), findsOneWidget);
      final ref1 = created1.canonicalOrderNumber ?? created1.provisionalOrderNumber;
      final ref2 = created2.canonicalOrderNumber ?? created2.provisionalOrderNumber;
      expect(find.text('أوردر #$ref1'), findsOneWidget);
      expect(find.text('أوردر #$ref2'), findsOneWidget);

      // 2. Open Invoices Screen
      final invoiceNav = find.text('سجل الفواتير');
      await tester.tap(invoiceNav.first);
      await tester.pumpFewFrames();

      expect(find.byType(InvoicesScreen), findsOneWidget);
      expect(find.text('أوردر #$ref2'), findsOneWidget);

      // Select the order to view receipt
      await tester.tap(find.text('أوردر #$ref2'));
      await tester.pumpFewFrames();

      expect(find.text('تفاصيل الفاتورة'), findsOneWidget);
      expect(find.text('3x فطيرة مشلتت عسل وقشطة'), findsWidgets);
      expect(find.text('عسل إضافي • قشطة بلدي'), findsOneWidget);
      expect(find.text('ملاحظة: تسوية زيادة ومقرمشة'), findsOneWidget);
    });
  });
}

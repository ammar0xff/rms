import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/app.dart';
import 'package:rms/src/domain/models/app_role.dart';
import 'package:rms/src/domain/models/order.dart';
import 'package:rms/src/domain/models/order_draft.dart';
import 'package:rms/src/domain/models/order_type.dart';
import 'package:rms/src/features/accounting/invoices_screen.dart';

import '../helpers/test_bootstrap.dart';

void main() {
  group('Invoices Screen & Receipt Flows', () {
    testWidgets('Invoices screen renders cleanly on desktop and allows selecting an invoice', (WidgetTester tester) async {
      tester.setDesktopSize();
      addTearDown(tester.resetTestSize);

      final services = await createTestServices(tester: tester, initialRole: AppRole.cashier);

      // Create an order
      final draft = OrderDraft(
        orderType: OrderType.takeaway,
        items: const [
          OrderItem(
            productId: 'p1',
            name: 'فطيرة كاسترد وسكر',
            unitPrice: 120.0,
            quantity: 2,
          ),
        ],
        taxAmount: 33.6,
        serviceAmount: 0.0,
      );
      final created = await services.orders!.createOrder(draft);

      await tester.pumpWidget(RmsApp(services: services));
      await tester.pumpFewFrames();

      // Navigate to Invoices Screen (سجل الفواتير)
      final invoiceNav = find.text('سجل الفواتير');
      expect(invoiceNav, findsWidgets);
      await tester.tap(invoiceNav.first);
      await tester.pumpFewFrames();

      expect(find.byType(InvoicesScreen), findsOneWidget);
      expect(find.text('ابحث برقم الأوردر...'), findsOneWidget);
      final ref = created.canonicalOrderNumber ?? created.provisionalOrderNumber;
      expect(find.text('أوردر #$ref'), findsOneWidget);

      // Tap on the invoice to open the receipt detail viewer
      await tester.tap(find.text('أوردر #$ref'));
      await tester.pumpFewFrames();

      // Verify receipt details are visible on desktop without crashing
      expect(find.text('تفاصيل الفاتورة'), findsOneWidget);
      expect(find.text('2x فطيرة كاسترد وسكر'), findsWidgets);
      expect(find.text('إعادة طباعة'), findsOneWidget);

      // Tap reprint button
      await tester.tap(find.text('إعادة طباعة'));
      await tester.pumpFewFrames();
      expect(find.textContaining('جاري إرسال أمر طباعة الفاتورة'), findsOneWidget);
    });

    testWidgets('Invoices screen renders cleanly on mobile and opens mobile receipt sheet', (WidgetTester tester) async {
      tester.setMobileSize();
      addTearDown(tester.resetTestSize);

      final services = await createTestServices(tester: tester, initialRole: AppRole.cashier);

      // Create an order
      final draft = OrderDraft(
        orderType: OrderType.delivery,
        items: const [
          OrderItem(
            productId: 'p2',
            name: 'بيتزا سجق شرقي',
            unitPrice: 180.0,
            quantity: 1,
          ),
        ],
        taxAmount: 25.2,
        serviceAmount: 0.0,
      );
      final created = await services.orders!.createOrder(draft);

      await tester.pumpWidget(RmsApp(services: services));
      await tester.pumpFewFrames();

      // Navigate to Invoices Screen (سجل الفواتير)
      final invoiceNav = find.text('سجل الفواتير');
      expect(invoiceNav, findsWidgets);
      await tester.tap(invoiceNav.first);
      await tester.pumpFewFrames();

      expect(find.byType(InvoicesScreen), findsOneWidget);
      final ref = created.canonicalOrderNumber ?? created.provisionalOrderNumber;
      expect(find.text('أوردر #$ref'), findsOneWidget);

      // Tap on the invoice to trigger mobile bottom sheet
      await tester.tap(find.text('أوردر #$ref'));
      await tester.pumpFewFrames();

      // Verify bottom sheet opened without unbounded layout crash
      expect(find.text('تفاصيل الفاتورة'), findsOneWidget);
      expect(find.text('1x بيتزا سجق شرقي'), findsWidgets);
      expect(find.text('إعادة طباعة'), findsOneWidget);
    });

    testWidgets('Invoices screen reactively reflects newly created orders without remounting', (WidgetTester tester) async {
      tester.setDesktopSize();
      addTearDown(tester.resetTestSize);

      final services = await createTestServices(tester: tester, initialRole: AppRole.cashier);

      // Start app with NO orders created yet
      await tester.pumpWidget(RmsApp(services: services));
      await tester.pumpFewFrames();

      // Navigate to Invoices Screen
      final invoiceNav = find.text('سجل الفواتير');
      await tester.tap(invoiceNav.first);
      await tester.pumpFewFrames();

      // Should show empty state
      expect(find.text('مفيش فواتير مطابقة'), findsOneWidget);
      expect(find.text('تحديث السجل'), findsWidgets);

      // Now an order is created asynchronously while the screen stays mounted in IndexedStack
      final draft = OrderDraft(
        orderType: OrderType.takeaway,
        items: const [
          OrderItem(productId: 'p99', name: 'حواوشي مخصوص', unitPrice: 85.0, quantity: 1),
        ],
        taxAmount: 11.9,
      );
      final created = await services.orders!.createOrder(draft);

      // Pump frames so stream listener triggers setState
      await tester.pumpFewFrames();

      // The new order is immediately visible!
      final ref = created.canonicalOrderNumber ?? created.provisionalOrderNumber;
      expect(find.text('أوردر #$ref'), findsOneWidget);
      expect(find.text('1x حواوشي مخصوص'), findsWidgets);
    });
  });
}

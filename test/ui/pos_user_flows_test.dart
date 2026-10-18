import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/app.dart';
import 'package:rms/src/domain/models/app_role.dart';
import 'package:rms/src/domain/models/delivery.dart';
import 'package:rms/src/domain/models/facility_settings.dart';
import 'package:rms/src/domain/models/order_type.dart';
import 'package:rms/src/features/pos/pos_checkout_dialog.dart';
import 'package:rms/src/features/pos/pos_screen.dart';

import '../helpers/test_bootstrap.dart';

void main() {
  group('POS User Flows & Scenarios', () {
    testWidgets('Takeaway Order Flow: adds items to cart, tenders cash, creates order and outbox',
        (WidgetTester tester) async {
      tester.setDesktopSize();
      addTearDown(tester.resetTestSize);

      final services = await createTestServices(tester: tester, initialRole: AppRole.cashier);

      await tester.pumpWidget(RmsApp(services: services));
      await tester.pumpFewFrames();

      // Verify POS Screen rendered
      expect(find.byType(PosScreen), findsOneWidget);
      expect(find.text('نوع الطلب:'), findsOneWidget);
      expect(find.text('تيك أواي (استلام)'), findsOneWidget);

      // Add 'بيتزا مارغريتا' to cart
      final pizzaItem = find.text('بيتزا مارغريتا').first;
      expect(pizzaItem, findsOneWidget);
      await tester.tap(pizzaItem);
      await tester.pumpFewFrames();

      // Check item appears in Cart Receipt Panel
      expect(find.text('الفاتورة الحالية'), findsOneWidget);
      expect(find.text('بيتزا مارغريتا'), findsNWidgets(2)); // 1 in catalog, 1 in receipt panel

      // Open Checkout Dialog
      final checkoutBtn = find.textContaining('المحاسبة والدفع');
      expect(checkoutBtn, findsOneWidget);
      await tester.tap(checkoutBtn);
      await tester.pumpFewFrames();

      // Verify PosCheckoutDialog is open
      expect(find.byType(PosCheckoutDialog), findsOneWidget);
      expect(find.textContaining('الدفع وإنهاء الفاتورة'), findsOneWidget);

      // Takeaway allows completing without customer details
      // Enter tender: tap "بالضبط" (Exact) quick chip
      final exactChip = find.text('بالضبط');
      expect(exactChip, findsOneWidget);
      await tester.tap(exactChip);
      await tester.pumpFewFrames();

      // Settle Order
      final settleBtn = find.textContaining('إنهاء الدفع');
      expect(settleBtn, findsOneWidget);

      await tester.tap(settleBtn);
      await tester.pumpFewFrames();

      // Verify checkout dialog dismissed
      expect(find.byType(PosCheckoutDialog), findsNothing);

      // Verify order recorded in database
      await tester.runAsync(() async {
        final orders = await services.orders!.listOrders();
        expect(orders.length, greaterThanOrEqualTo(1));
        final order = orders.first;
        expect(order.orderType, OrderType.takeaway);
        expect(order.items.any((i) => i.name == 'بيتزا مارغريتا'), isTrue);

        // Verify outbox has createOrder entry
        final outboxEntries = await services.outbox!.all();
        expect(outboxEntries.any((e) => e.entityType == 'order'), isTrue);
      });
    });

    testWidgets('Delivery Order Validation Flow: requires customer name, phone, address when delivery',
        (WidgetTester tester) async {
      tester.setDesktopSize();
      addTearDown(tester.resetTestSize);

      final services = await createTestServices(tester: tester, initialRole: AppRole.cashier);

      await tester.pumpWidget(RmsApp(services: services));
      await tester.pumpFewFrames();

      // Switch to Delivery Channel
      final deliveryChip = find.text('دليفري (توصيل)');
      expect(deliveryChip, findsOneWidget);
      await tester.tap(deliveryChip);
      await tester.pumpFewFrames();

      // Add item to cart
      final pizzaItem = find.text('بيتزا مارغريتا').first;
      await tester.tap(pizzaItem);
      await tester.pumpFewFrames();

      // Open Checkout Dialog
      final checkoutBtn = find.textContaining('المحاسبة والدفع');
      await tester.tap(checkoutBtn);
      await tester.pumpFewFrames();

      expect(find.byType(PosCheckoutDialog), findsOneWidget);

      // Attempt to submit without entering name / phone / address
      final exactChip = find.text('بالضبط');
      await tester.tap(exactChip);
      await tester.pumpFewFrames();

      final settleBtn = find.textContaining('إنهاء الدفع');
      await tester.tap(settleBtn);
      await tester.pumpFewFrames();

      // Verification fails: Error messages must appear and dialog remains open
      expect(find.text('مطلوب'), findsWidgets);
      expect(find.byType(PosCheckoutDialog), findsOneWidget);

      // Now enter valid customer details
      final textFields = find.byType(TextField);
      expect(textFields, findsNWidgets(3)); // name, phone, address

      await tester.enterText(textFields.at(0), 'كريم الدسوقي');
      await tester.enterText(textFields.at(1), '01099887766');
      await tester.enterText(textFields.at(2), 'المعادي شارع 9 عمارة 4');
      await tester.pumpFewFrames();

      // Settle again
      await tester.tap(settleBtn);
      await tester.pumpFewFrames();

      // Verify dialog dismissed
      expect(find.byType(PosCheckoutDialog), findsNothing);

      // Verify delivery order was created with customer info
      await tester.runAsync(() async {
        final orders = await services.orders!.listOrders();
        final order = orders.first;
        expect(order.orderType, OrderType.delivery);

        // Verify delivery record created
        final deliveries = await services.deliveries!.listDeliveries();
        expect(deliveries.any((d) => d.orderRef == order.localId || d.orderRef == order.provisionalOrderNumber), isTrue);
      });
    });

    testWidgets('Manual Driver Assignment Flow: pops up manual assign dialog when autoDispatch is disabled',
        (WidgetTester tester) async {
      tester.setDesktopSize();
      addTearDown(tester.resetTestSize);

      final services = await createTestServices(tester: tester, initialRole: AppRole.cashier);

      // Set facility settings autoAssignDelivery to false
      await tester.runAsync(() async {
        await services.facility!.save(
          const FacilitySettings(autoAssignDelivery: false),
        );
      });

      await tester.pumpWidget(RmsApp(services: services));
      await tester.pumpFewFrames();

      // Switch to Delivery Channel
      await tester.tap(find.text('دليفري (توصيل)'));
      await tester.pumpFewFrames();

      // Add item
      await tester.tap(find.text('بيتزا مارغريتا').first);
      await tester.pumpFewFrames();

      // Open Checkout
      await tester.tap(find.textContaining('المحاسبة والدفع'));
      await tester.pumpFewFrames();

      // Enter customer info
      final textFields = find.byType(TextField);
      await tester.enterText(textFields.at(0), 'سامي فؤاد');
      await tester.enterText(textFields.at(1), '01234567890');
      await tester.enterText(textFields.at(2), 'مدينة نصر');
      await tester.pumpFewFrames();

      // Select exact cash
      await tester.tap(find.text('بالضبط'));
      await tester.pumpFewFrames();

      // Settle order
      await tester.tap(find.textContaining('إنهاء الدفع'));
      await tester.pumpFewFrames();

      // Manual driver assignment dialog must pop up!
      expect(find.text('إسناد يدوي لسائق التوصيل'), findsOneWidget);
      expect(find.textContaining('إسناد للكابتن'), findsOneWidget);

      // Confirm assignment
      await tester.tap(find.textContaining('إسناد للكابتن'));
      await tester.pumpFewFrames();

      // Verify dialog is closed
      expect(find.text('إسناد يدوي لسائق التوصيل'), findsNothing);

      // Verify delivery has driver assigned
      await tester.runAsync(() async {
        final deliveries = await services.deliveries!.listDeliveries();
        final assigned = deliveries.where((d) => d.state == DeliveryState.assigned || d.state == DeliveryState.onRoute);
        expect(assigned, isNotEmpty);
      });
    });
  });
}

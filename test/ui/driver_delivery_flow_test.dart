import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/app.dart';
import 'package:rms/src/domain/models/app_role.dart';
import 'package:rms/src/domain/models/collection.dart';
import 'package:rms/src/domain/models/delivery.dart';
import 'package:rms/src/features/delivery/active_trip_screen.dart';
import 'package:rms/src/features/delivery/custody_settlement_screen.dart';
import 'package:rms/src/features/delivery/driver_fail_dialog.dart';
import 'package:rms/src/features/delivery/driver_identity_service.dart';
import 'package:rms/src/features/delivery/driver_nav_sheet.dart';
import 'package:rms/src/features/delivery/driver_receipt_sheet.dart';

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
      final navBtn = find.text('الملاحة وخريطة السير');
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
      final receiptBtn = find.text('عرض البون');
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
      final deliverBtn = find.text('تم التسليم بنجاح');
      expect(deliverBtn, findsOneWidget);
      await tester.tap(deliverBtn);
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
  });
}

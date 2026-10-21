import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/app.dart';
import 'package:rms/src/domain/models/app_role.dart';
import 'package:rms/src/domain/models/cash_session.dart';
import 'package:rms/src/domain/models/order.dart';
import 'package:rms/src/features/accounting/z_report_screen.dart';
import 'package:rms/src/features/shift/shift_screen.dart';

import '../helpers/test_bootstrap.dart';

void main() {
  group('Shift Session & Z-Close Flows', () {
    testWidgets('Active shift metrics and order channel filter flow', (WidgetTester tester) async {
      tester.setDesktopSize();
      addTearDown(tester.resetTestSize);

      final services = await createTestServices(tester: tester, initialRole: AppRole.cashier);

      await tester.pumpWidget(RmsApp(services: services));
      await tester.pumpFewFrames();

      // Navigate to Shift Screen (الوردية والخزينة)
      final shiftNav = find.text('الوردية والخزينة');
      expect(shiftNav, findsWidgets);
      await tester.tap(shiftNav.first);
      await tester.pumpFewFrames();

      // Verify ShiftScreen is visible and displays active shift
      expect(find.byType(ShiftScreen), findsOneWidget);
      expect(find.text('الوردية مفتوحة ومباشرة'), findsOneWidget);
      expect(find.text('عهدة الافتتاح (Float)'), findsOneWidget);
      expect(find.text('الرصيد المحسوب بالدرج'), findsOneWidget);

      // Verify channel filter chips
      expect(find.text('الكل'), findsOneWidget);
      expect(find.text('تيك أواي'), findsOneWidget);
      expect(find.text('دليفري'), findsOneWidget);

      // Tap 'تيك أواي' chip
      await tester.tap(find.text('تيك أواي'));
      await tester.pumpFewFrames();

      // Tap 'دليفري' chip
      await tester.tap(find.text('دليفري'));
      await tester.pumpFewFrames();

      // Reset to 'الكل'
      await tester.tap(find.text('الكل'));
      await tester.pumpFewFrames();
    });

    testWidgets('Z-Report Cash Count & Drawer Close Flow', (WidgetTester tester) async {
      tester.setDesktopSize();
      addTearDown(tester.resetTestSize);

      final services = await createTestServices(tester: tester, initialRole: AppRole.cashier);

      await tester.pumpWidget(RmsApp(services: services));
      await tester.pumpFewFrames();

      // Navigate to Shift Screen
      await tester.tap(find.text('الوردية والخزينة').first);
      await tester.pumpFewFrames();

      // Tap fast path to Z-Report
      final zReportBtn = find.text('جرد الكاش وتقفيل الوردية (Z-Report)');
      expect(zReportBtn, findsOneWidget);
      await tester.tap(zReportBtn);
      await tester.pumpFewFrames();

      // Verify ZReportScreen is pushed
      expect(find.byType(ZReportScreen), findsOneWidget);
      expect(find.text('فئات النقدية بالدرج'), findsNothing); // In desktop layout it uses Row with denominations
      expect(find.text('الرصيد المحسوب بالدفتر:'), findsOneWidget);
      expect(find.text('الرصيد الفعلي المجرود:'), findsOneWidget);

      // Tap denomination steppers: add one 200 note and one 100 note
      final addButtons = find.byIcon(Icons.add_circle_outline_rounded);
      expect(addButtons, findsWidgets);

      // First add button is for 200 LE
      await tester.tap(addButtons.at(0));
      await tester.pumpFewFrames();

      // Second add button is for 100 LE
      await tester.tap(addButtons.at(1));
      await tester.pumpFewFrames();

      // Verify Close Button is active and tap it
      final closeBtn = find.text('إتمام تقفيل الوردية Z-Close');
      expect(closeBtn, findsOneWidget);
      await tester.tap(closeBtn);
      await tester.pumpFewFrames();

      // Verify confirmation dialog
      expect(find.text('تأكيد تقفيل الوردية (Z-Close)'), findsOneWidget);
      final confirmBtn = find.text('أكّد التقفيل');
      expect(confirmBtn, findsOneWidget);

      await tester.tap(confirmBtn);
      await tester.pumpFewFrames();

      // ZReportScreen should be popped, back to ShiftScreen
      expect(find.byType(ZReportScreen), findsNothing);
      expect(find.byType(ShiftScreen), findsOneWidget);

      // Shift is now closed!
      expect(find.text('الوردية مقفولة'), findsOneWidget);
      expect(find.text('فتح وردية جديدة وتعيين العهدة'), findsOneWidget);

      // Verify session state in repository
      await tester.runAsync(() async {
        final current = await services.cashSessions!.currentSession();
        expect(current, isNull);

        final sessions = await services.cashSessions!.listSessions();
        expect(sessions.any((s) => s.status == CashSessionStatus.closed && s.countedCash == 300.0), isTrue);
      });
    });

    testWidgets('Open New Shift Flow: opens dialog, sets float, opens session', (WidgetTester tester) async {
      tester.setDesktopSize();
      addTearDown(tester.resetTestSize);

      final services = await createTestServices(tester: tester, initialRole: AppRole.cashier);

      // Close any active session first in DB
      await tester.runAsync(() async {
        final current = await services.cashSessions!.currentSession();
        if (current != null) {
          await services.cashSessions!.closeSession(current.id, countedCash: 200);
        }
      });

      await tester.pumpWidget(RmsApp(services: services));
      await tester.pumpFewFrames();

      // Navigate to Shift Screen
      await tester.tap(find.text('الوردية والخزينة').first);
      await tester.pumpFewFrames();

      expect(find.text('الوردية مقفولة'), findsOneWidget);
      final openBtn = find.text('فتح وردية جديدة وتعيين العهدة');
      expect(openBtn, findsOneWidget);

      await tester.tap(openBtn);
      await tester.pumpFewFrames();

      // Verify Open Shift Dialog
      expect(find.text('افتتاح وردية جديدة'), findsOneWidget);
      expect(find.text('+500 ج.م'), findsOneWidget);

      // Tap +500 chip
      await tester.tap(find.text('+500 ج.م'));
      await tester.pumpFewFrames();

      // Confirm
      await tester.tap(find.text('فتح الوردية الآن'));
      await tester.pumpFewFrames();

      // Verify dialog dismissed and shift is open
      expect(find.text('افتتاح وردية جديدة'), findsNothing);
      expect(find.text('الوردية مفتوحة ومباشرة'), findsOneWidget);

      // Verify in DB
      await tester.runAsync(() async {
        final current = await services.cashSessions!.currentSession();
        expect(current, isNotNull);
        expect(current!.isOpen, isTrue);
        expect(current.openingFloat, 500.0);
      });
    });

    testWidgets('Shift Screen renders cleanly on mobile viewport', (WidgetTester tester) async {
      tester.setMobileSize();
      addTearDown(tester.resetTestSize);

      final services = await createTestServices(tester: tester, initialRole: AppRole.cashier);

      await tester.pumpWidget(RmsApp(services: services));
      await tester.pumpFewFrames();

      // Navigate to Shift Screen
      final shiftNav = find.text('الوردية والخزينة');
      expect(shiftNav, findsWidgets);
      await tester.tap(shiftNav.first);
      await tester.pumpFewFrames();

      // Verify ShiftScreen is visible without errors
      expect(find.byType(ShiftScreen), findsOneWidget);
      expect(find.text('الوردية مفتوحة ومباشرة'), findsOneWidget);
      expect(find.text('تذاكر الأوردرات اللحظية'), findsOneWidget);
    });

    testWidgets('Shift Screen renders cleanly on tablet viewport without unbounded flex errors', (WidgetTester tester) async {
      tester.setTabletSize();
      addTearDown(tester.resetTestSize);

      final services = await createTestServices(tester: tester, initialRole: AppRole.cashier);

      await tester.pumpWidget(RmsApp(services: services));
      await tester.pumpFewFrames();

      // Navigate to Shift Screen
      final shiftNav = find.text('الوردية والخزينة');
      expect(shiftNav, findsWidgets);
      await tester.tap(shiftNav.first);
      await tester.pumpFewFrames();

      // Verify ShiftScreen is visible without errors
      expect(find.byType(ShiftScreen), findsOneWidget);
      expect(find.text('الوردية مفتوحة ومباشرة'), findsOneWidget);
      expect(find.text('تذاكر الأوردرات اللحظية'), findsOneWidget);
    });

    test('CashSession.fromRecord handles null and missing fields defensively', () {
      final session = CashSession.fromRecord({
        'id': 'sess-123',
      });
      expect(session.id, 'sess-123');
      expect(session.isOpen, isTrue);
      expect(session.openingFloat, 500.0);
      expect(session.status, CashSessionStatus.open);
    });

    test('Order.fromRecord handles null and missing fields defensively', () {
      final order = Order.fromRecord({
        'localId': 'ord-123',
        'provisionalOrderNumber': '101',
      });
      expect(order.localId, 'ord-123');
      expect(order.provisionalOrderNumber, '101');
      expect(order.items, isEmpty);
      expect(order.createdOffline, isFalse);
    });
  });
}

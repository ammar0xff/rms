import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/app.dart';
import 'package:rms/src/data/local/local_stores.dart';
import 'package:rms/src/domain/models/app_role.dart';
import 'package:rms/src/features/pos/pos_screen.dart';
import 'package:sembast/sembast.dart';

import '../helpers/test_bootstrap.dart';

void main() {
  group('POS Shift Gating & Sales Protection Flow', () {
    testWidgets(
      'Gating Gate Flow: POS blocks sales when shift is closed and unlocks when opened',
      (WidgetTester tester) async {
        tester.setDesktopSize();
        addTearDown(tester.resetTestSize);

        final services = await createTestServices(
          tester: tester,
          initialRole: AppRole.cashier,
        );

        // 1. Delete any open seeded session to simulate closed shift state
        await LocalStores.cashSessions.delete(services.database!.db);

        await tester.pumpWidget(RmsApp(services: services));
        await tester.pumpFewFrames();

        // 2. Verify POS is locked and Shift Required Gate is displayed
        expect(find.byType(PosScreen), findsOneWidget);
        expect(find.text('الوردية مغلقة — يرجى فتح الوردية للبدء'), findsOneWidget);
        expect(
          find.text('افتتاح الوردية وتعيين العهدة الآن'),
          findsOneWidget,
        );
        // Catalog should NOT be visible while gated
        expect(find.text('نوع الطلب:'), findsNothing);

        // 3. Tap "افتتاح الوردية وتعيين العهدة الآن" to open shift dialog
        await tester.tap(find.text('افتتاح الوردية وتعيين العهدة الآن'));
        await tester.pumpFewFrames();

        // Verify OpenShiftDialog appeared
        expect(find.text('افتتاح وردية جديدة'), findsOneWidget);
        expect(find.text('+1000 ج.م'), findsOneWidget);

        // Tap chip for +1000 EGP
        await tester.tap(find.text('+1000 ج.م'));
        await tester.pumpFewFrames();

        // Tap confirm "فتح الوردية الآن"
        await tester.tap(find.text('فتح الوردية الآن'));
        await tester.pumpFewFrames();

        // 4. POS should reactively unlock immediately
        expect(find.text('الوردية مغلقة — يرجى فتح الوردية للبدء'), findsNothing);
        expect(find.text('نوع الطلب:'), findsOneWidget);
        expect(find.text('تيك أواي (استلام)'), findsOneWidget);
        // Green badge removed from channel bar:
        expect(find.textContaining('الوردية مفتوحة'), findsNothing);
        // Drawer cash and close shift button moved to top level bar:
        expect(find.text('نقدية الدرج: '), findsOneWidget);
        expect(find.text('إغلاق الوردية'), findsOneWidget);

        // 5. Verify adding item to cart works now
        final itemFinder = find.text('بيتزا مارغريتا').first;
        expect(itemFinder, findsOneWidget);
        await tester.tap(itemFinder);
        await tester.pumpFewFrames();

        expect(find.text('الفاتورة الحالية'), findsOneWidget);

        // 6. Close the shift and verify POS gates again
        final current = await services.cashSessions!.currentSession();
        expect(current, isNotNull);
        await services.cashSessions!.closeSession(current!.id, countedCash: 1000);
        await tester.pumpFewFrames();

        // POS should be locked again
        expect(find.text('الوردية مغلقة — يرجى فتح الوردية للبدء'), findsOneWidget);
        expect(find.text('نوع الطلب:'), findsNothing);
      },
    );

    testWidgets(
      'Cart and Checkout Guard: prevents adding item or checkout if shift closed',
      (WidgetTester tester) async {
        tester.setDesktopSize();
        addTearDown(tester.resetTestSize);

        final services = await createTestServices(
          tester: tester,
          initialRole: AppRole.cashier,
        );

        // Start with open session
        await tester.pumpWidget(RmsApp(services: services));
        await tester.pumpFewFrames();

        // Add item to cart
        final itemFinder = find.text('بيتزا مارغريتا').first;
        await tester.tap(itemFinder);
        await tester.pumpFewFrames();
        expect(find.text('الفاتورة الحالية'), findsOneWidget);

        // Close session behind the scenes
        final current = await services.cashSessions!.currentSession();
        expect(current, isNotNull);
        await services.cashSessions!.closeSession(current!.id, countedCash: 500);
        await tester.pumpFewFrames();

        // Blocker gate is presented
        expect(find.text('الوردية مغلقة — يرجى فتح الوردية للبدء'), findsOneWidget);
      },
    );

    testWidgets(
      'POS Channel Bar renders single close button and non-duplicated cash float',
      (WidgetTester tester) async {
        tester.setDesktopSize();
        addTearDown(tester.resetTestSize);

        final services = await createTestServices(
          tester: tester,
          initialRole: AppRole.cashier,
        );

        final current = await services.cashSessions!.currentSession();
        if (current != null) {
          await services.cashSessions!.closeSession(current.id, countedCash: 0);
        }
        await services.cashSessions!.openSession(
          openingFloat: 500,
          cashierUid: 'test-cashier',
          cashierName: 'كاشير وردية',
        );

        await tester.pumpWidget(RmsApp(services: services));
        await tester.pumpFewFrames();

        // 1. Verify single dedicated 'إغلاق الوردية' button on top level bar
        expect(find.text('إغلاق الوردية'), findsOneWidget);

        // 2. Verify green badge 'الوردية مفتوحة' is removed
        expect(find.textContaining('الوردية مفتوحة'), findsNothing);

        // 3. Verify 'نقدية الدرج: ' and '500.00' are rendered on the top level bar
        expect(find.text('نقدية الدرج: '), findsOneWidget);
        expect(find.textContaining('500.00'), findsOneWidget);
        expect(find.textContaining('عهدة البداية'), findsNothing);
        expect(find.textContaining('العهدة:'), findsNothing);

        // 4. Tap 'إغلاق الوردية' on top level bar and verify navigation to ZReportScreen
        await tester.tap(find.text('إغلاق الوردية'));
        await tester.pumpFewFrames();
        expect(find.text('الرصيد المحسوب بالدفتر:'), findsOneWidget);
      },
    );
  });
}


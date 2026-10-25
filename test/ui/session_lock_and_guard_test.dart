import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/app.dart';
import 'package:rms/src/domain/models/app_role.dart';
import 'package:rms/src/features/accounting/z_report_screen.dart';

import '../helpers/test_bootstrap.dart';

void main() {
  group('Session Quick Lock & Sign-Out Guard Tests', () {
    testWidgets('Quick lock button toggles lock overlay and unlock button restores screen', (tester) async {
      tester.setDesktopSize();
      addTearDown(tester.resetTestSize);

      final services = await createTestServices(
        tester: tester,
        initialRole: AppRole.cashier,
      );

      await tester.pumpWidget(RmsApp(services: services));
      await tester.pumpFewFrames();

      // Find quick lock button
      final lockButton = find.byTooltip('قفل الشاشة السريع');
      expect(lockButton, findsOneWidget);

      // Tap lock button
      await tester.tap(lockButton);
      await tester.pumpFewFrames();

      // Lock overlay should appear
      expect(find.text('الشاشة مقفلة مؤقتاً'), findsOneWidget);
      expect(find.text('فتح القفل ومتابعة العمل'), findsOneWidget);

      // Tap unlock button
      await tester.tap(find.text('فتح القفل ومتابعة العمل'));
      await tester.pumpFewFrames();

      // Lock overlay dismissed
      expect(find.text('الشاشة مقفلة مؤقتاً'), findsNothing);
    });

    testWidgets('Sign-out guard detects open cash shift and displays warning with Z-report action', (tester) async {
      tester.setDesktopSize();
      addTearDown(tester.resetTestSize);

      final services = await createTestServices(
        tester: tester,
        initialRole: AppRole.cashier,
      );

      // Clear any pre-existing demo session first
      final current = await services.cashSessions!.currentSession();
      if (current != null) {
        await services.cashSessions!.closeSession(current.id, countedCash: 0);
      }

      // Open a session with custom cashier info and float
      await services.cashSessions!.openSession(
        openingFloat: 750,
        cashierUid: 'test-cashier-1',
        cashierName: 'أحمد محمود',
      );

      await tester.pumpWidget(RmsApp(services: services));
      await tester.pumpFewFrames();

      // Tap sign-out button
      final signOutButton = find.byTooltip('تسجيل الخروج');
      expect(signOutButton, findsOneWidget);
      await tester.tap(signOutButton);
      await tester.pumpFewFrames();

      // Check warning in confirmation dialog
      expect(find.text('تنبيه: توجد وردية نقدية مفتوحة!'), findsOneWidget);
      expect(find.textContaining('الوردية الحالية مفتوحة برأس مال 750.00 ج.م'), findsOneWidget);
      expect(find.textContaining('المسؤول: أحمد محمود'), findsOneWidget);
      expect(find.text('الانتقال لتقفيل Z الآن'), findsOneWidget);

      // Tap "الانتقال لتقفيل Z الآن"
      await tester.tap(find.text('الانتقال لتقفيل Z الآن'));
      await tester.pumpFewFrames();

      // Should close dialog and navigate to Z-Report tab
      expect(find.text('تنبيه: توجد وردية نقدية مفتوحة!'), findsNothing);
      expect(find.byType(ZReportScreen), findsOneWidget);
    });
  });
}

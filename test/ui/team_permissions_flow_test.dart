import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/app.dart';
import 'package:rms/src/domain/models/app_role.dart';
import 'package:rms/src/domain/models/approval_request.dart';
import 'package:rms/src/core/widgets/pie_card.dart';
import 'package:rms/src/features/manager/approvals_screen.dart';
import 'package:rms/src/features/manager/pin_delegation_dialog.dart';
import 'package:rms/src/features/manager/team_screen.dart';

import '../helpers/test_bootstrap.dart';

void main() {
  group('Manager Approvals & Team Permissions Flows', () {
    testWidgets('Approvals Flow: view pending requests, verify PIN 1234, approve refund',
        (WidgetTester tester) async {
      tester.setDesktopSize();
      addTearDown(tester.resetTestSize);

      final services = await createTestServices(
        tester: tester,
        initialRole: AppRole.manager,
      );

      await tester.pumpWidget(RmsApp(services: services));
      await tester.pumpFewFrames();

      // Navigate to Approvals screen (الموافقات)
      final approvalsTab = find.text('الموافقات');
      expect(approvalsTab, findsWidgets);
      await tester.tap(approvalsTab.first);
      await tester.pumpFewFrames();

      // Verify ApprovalsScreen is rendered
      expect(find.byType(ApprovalsScreen), findsOneWidget);
      expect(find.text('طلبات معلقة بالانتظار'), findsOneWidget);
      expect(find.textContaining('ORD-4791'), findsOneWidget);
      expect(find.textContaining('طبق مُعاد من العميل'), findsOneWidget);

      // Tap 'اعتماد بـ PIN'
      final approveBtn = find.text('اعتماد بـ PIN');
      expect(approveBtn, findsOneWidget);
      await tester.tap(approveBtn);
      await tester.pumpFewFrames();

      // Verify PIN delegation dialog opened
      expect(find.byType(PinDelegationDialog), findsOneWidget);
      expect(find.textContaining('اعتماد استرجاع'), findsOneWidget);

      // Enter manager PIN: 1, 2, 3, 4
      for (final digit in ['1', '2', '3', '4']) {
        final keyBtn = find.descendant(
          of: find.byType(PinDelegationDialog),
          matching: find.text(digit),
        );
        expect(keyBtn, findsOneWidget);
        await tester.tap(keyBtn);
        await tester.pump(const Duration(milliseconds: 50));
      }

      await tester.pumpFewFrames();

      // Verify dialog dismissed
      expect(find.byType(PinDelegationDialog), findsNothing);

      // Verify request is approved in repository
      await tester.runAsync(() async {
        final requests = await services.approvals!.listRequests();
        final req = requests.firstWhere((r) => r.id == 'AP-0001');
        expect(req.status, ApprovalStatus.approved);
        expect(req.decidedBy, 'المدير العام');
      });

      // Verify empty state is now displayed
      expect(find.text('مفيش طلبات معلقة للاعتماد'), findsOneWidget);
    });

    testWidgets('Reject Flow: reject request with mandatory note',
        (WidgetTester tester) async {
      tester.setDesktopSize();
      addTearDown(tester.resetTestSize);

      final services = await createTestServices(
        tester: tester,
        initialRole: AppRole.manager,
      );

      // Seed an additional void order approval request
      await tester.runAsync(() async {
        await services.approvals!.requestVoid(
          orderLocalId: 'ORD-9999',
          orderRef: 'ORD-9999',
          amount: 85.0,
          reason: 'إلغاء الطلب بناء على رغبة العميل',
          requestedBy: 'كاشير الكاونتر',
        );
      });

      await tester.pumpWidget(RmsApp(services: services));
      await tester.pumpFewFrames();

      // Switch to Approvals screen
      final approvalsTab = find.text('الموافقات');
      expect(approvalsTab, findsWidgets);
      await tester.tap(approvalsTab.first);
      await tester.pumpFewFrames();

      expect(find.textContaining('ORD-9999'), findsOneWidget);

      // Tap 'رفض الطلب' on the newly seeded void request card
      final ordCard = find.ancestor(
        of: find.textContaining('ORD-9999'),
        matching: find.byType(PieCard),
      );
      final rejectBtn = find.descendant(
        of: ordCard,
        matching: find.text('رفض الطلب'),
      );
      expect(rejectBtn, findsOneWidget);
      await tester.tap(rejectBtn);
      await tester.pumpFewFrames();

      // Verify rejection dialog
      expect(find.textContaining('رفض'), findsWidgets);
      expect(find.text('اكتب سبب رفض الطلب ليتم إبلاغ الكاشير بالسبب:'), findsOneWidget);

      // Enter rejection note
      final textField = find.byType(TextField);
      expect(textField, findsOneWidget);
      await tester.enterText(textField, 'الطلب تم تحضيره بالفعل ولا يمكن إلغاؤه');
      await tester.pumpFewFrames();

      // Tap 'أكّد الرفض'
      final confirmRejectBtn = find.text('أكّد الرفض');
      expect(confirmRejectBtn, findsOneWidget);
      await tester.tap(confirmRejectBtn);
      await tester.pumpFewFrames();

      // Verify dialog dismissed
      expect(find.text('اكتب سبب رفض الطلب ليتم إبلاغ الكاشير بالسبب:'), findsNothing);

      // Verify request state in repository is rejected
      await tester.runAsync(() async {
        final requests = await services.approvals!.listRequests();
        final rejectedReq = requests.firstWhere((r) => r.orderRef == 'ORD-9999');
        expect(rejectedReq.status, ApprovalStatus.rejected);
        expect(rejectedReq.decidedNote, 'الطلب تم تحضيره بالفعل ولا يمكن إلغاؤه');
      });
    });

    testWidgets('Team Roster Flow: filter roles, inspect member details, edit role & permissions',
        (WidgetTester tester) async {
      tester.setDesktopSize();
      addTearDown(tester.resetTestSize);

      final services = await createTestServices(
        tester: tester,
        initialRole: AppRole.manager,
      );

      await tester.pumpWidget(RmsApp(services: services));
      await tester.pumpFewFrames();

      // Switch to Team tab (فريق العمل)
      final teamTab = find.text('فريق العمل');
      expect(teamTab, findsWidgets);
      await tester.tap(teamTab.first);
      await tester.pumpFewFrames();

      // Verify TeamScreen rendered
      expect(find.byType(TeamScreen), findsOneWidget);
      expect(find.text('فريق العمل والصلاحيات'), findsOneWidget);

      // Verify members present
      expect(find.text('أحمد محمود'), findsOneWidget);
      expect(find.text('طارق حسام'), findsOneWidget);

      // Filter by 'كاشير'
      final cashierFilter = find.textContaining('كاشير (2)');
      expect(cashierFilter, findsOneWidget);
      await tester.tap(cashierFilter);
      await tester.pumpFewFrames();

      // Verify Ahmed is shown, Tarek is filtered out
      expect(find.text('أحمد محمود'), findsOneWidget);
      expect(find.text('طارق حسام'), findsNothing);

      // Reset filter to 'الكل'
      final allFilter = find.textContaining('الكل');
      expect(allFilter, findsOneWidget);
      await tester.tap(allFilter);
      await tester.pumpFewFrames();

      expect(find.text('طارق حسام'), findsOneWidget);

      // Tap on Ahmed Mahmoud to inspect details
      await tester.tap(find.text('أحمد محمود'));
      await tester.pumpFewFrames();

      // Verify details pane
      expect(find.textContaining('مصفوفة صلاحيات: أحمد محمود'), findsOneWidget);
      expect(find.text('الصلاحيات المباشرة'), findsOneWidget);

      // Tap 'تعديل الصلاحيات' button
      final editPermBtn = find.text('تعديل الصلاحيات').first;
      await tester.tap(editPermBtn);
      await tester.pumpFewFrames();

      // Verify dialog
      expect(find.textContaining('تعديل دور وصلاحيات أحمد محمود'), findsOneWidget);
      expect(find.text('الدور الوظيفي للموظف:'), findsOneWidget);

      // Tap 'حفظ التعديلات'
      final saveBtn = find.text('حفظ التعديلات');
      expect(saveBtn, findsOneWidget);
      await tester.tap(saveBtn);
      await tester.pumpFewFrames();

      // Dialog dismissed
      expect(find.textContaining('تعديل دور وصلاحيات أحمد محمود'), findsNothing);
    });
  });
}

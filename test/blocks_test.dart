import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/core/theme/app_colors.dart';
import 'package:rms/src/core/theme/app_theme.dart';
import 'package:rms/src/core/widgets/blocks.dart';
import 'package:rms/src/core/widgets/buttons.dart';
import 'package:rms/src/core/widgets/status.dart';

/// Phase-1 blocks must hold long Egyptian copy at phone width, including
/// their interactive states (expanded, filtered, filled).
Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('phase-1 blocks at 390px', () {
    testWidgets('dialog shell with long copy and actions', (tester) async {
      await _pump(
        tester,
        DialogShell(
          title: 'تسجيل تحصيل مبلغ كبير من العميل',
          subtitle: 'راجع المبلغ قبل التسجيل لأنه يرحّل للمخزون والسجل',
          content: const Text('محتوى طويل يشرح كل التفاصيل المطلوبة'),
          actions: [
            RmsButton(
                label: 'إلغاء', onPressed: () {}, variant: BtnVariant.ghost),
            RmsButton(label: 'احفظ التحصيل الكبير', onPressed: () {}),
          ],
        ),
      );

      expect(find.text('احفظ التحصيل الكبير'), findsOneWidget);
    });

    testWidgets('list toolbar with filters', (tester) async {
      var query = '';
      var filter = 0;
      await _pump(
        tester,
        StatefulBuilder(
          builder: (context, setState) => ListToolbar(
            hint: 'دوّر في القائمة الطويلة دي',
            onQuery: (v) => setState(() => query = v),
            filters: const ['الكل', 'المشويات الطويلة', 'الفرن'],
            selected: filter,
            onFilter: (i) => setState(() => filter = i),
            action: RmsButton(label: 'ضيف', onPressed: () {}),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'دجاج');
      await tester.pumpAndSettle();
      expect(query, 'دجاج');
      await tester.ensureVisible(find.text('الفرن'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('الفرن'));
      await tester.pumpAndSettle();
      expect(filter, 2);
    });

    testWidgets('collapsible folds and unfolds', (tester) async {
      await _pump(
        tester,
        const Collapsible(
          title: 'شرح طويل لسياسة إعادة المحاولة الآمنة',
          child: Text('تفاصيل التفاصيل التفاصيل'),
        ),
      );

      expect(find.text('تفاصيل التفاصيل التفاصيل'), findsNothing);
      await tester.tap(find.text('شرح طويل لسياسة إعادة المحاولة الآمنة'));
      await tester.pumpAndSettle();
      expect(find.text('تفاصيل التفاصيل التفاصيل'), findsOneWidget);
    });

    testWidgets('timeline with trailing amounts', (tester) async {
      await _pump(
        tester,
        const TimelineList(entries: [
          TimelineEntry(
            tone: StatusTone.warning,
            title: 'طلب-توصيل-طويل-001 في الطريق للعميل',
            subtitle: 'شارع الجمهورية الطويل، عمارة ١٢',
            trailing: Text('240.75'),
          ),
          TimelineEntry(
            tone: StatusTone.positive,
            title: 'طلب-002 اتسلّم واتحصّل',
          ),
        ]),
      );

      expect(find.text('240.75'), findsOneWidget);
    });

    testWidgets('skeletons render', (tester) async {
      // The pulse repeats forever, so pumpAndSettle would never finish:
      // pump once and assert the shapes exist.
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  SkeletonBox(width: 200),
                  SizedBox(height: 8),
                  SkeletonBox(height: 48),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(SkeletonBox), findsNWidgets(2));
    });

    testWidgets('mix bars normalize', (tester) async {
      await _pump(
        tester,
        const MixBars(entries: [
          MixEntry(label: 'كاش', value: 5000, color: AppColors.positive),
          MixEntry(label: 'فيزا طويلة', value: 3000, color: AppColors.info),
          MixEntry(label: 'مرتجعات', value: 320, color: AppColors.warning),
        ]),
      );

      expect(find.text('فيزا طويلة'), findsOneWidget);
    });
  });
}

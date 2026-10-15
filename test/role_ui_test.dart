import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/core/theme/app_theme.dart';
import 'package:rms/src/core/widgets/role_ui.dart';
import 'package:rms/src/core/widgets/status.dart';
import 'package:rms/src/domain/models/app_role.dart';

/// The role-home building blocks must be overflow-proof with long Egyptian
/// copy at phone width, like every other surface in the app.
Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: SingleChildScrollView(child: child),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('role home primitives at 390px', () {
    for (final role in AppRole.values) {
      testWidgets('hero renders for ${role.name}', (tester) async {
        await _pump(
          tester,
          RoleHero(
            role: role,
            kicker: 'شيفت النهاردة · الفرع الرئيسي',
            title: 'عنوان طويل للشاشة الرئيسية للدور الحالي',
            subtitle: 'سطر وصفي طويل يشرح الحالة الحالية للوردية والمهام المستنية',
            value: '8,412.50',
            valueLabel: 'جنيه مصري',
          ),
        );

        expect(find.text('8,412.50'), findsOneWidget);
      });
    }

    testWidgets('kpi card with delta', (tester) async {
      await _pump(
        tester,
        const KpiCard(
          label: 'صافي مبيعات النهاردة الطويل',
          value: '12,400.75',
          delta: '+18% عن امبارح',
          deltaGood: true,
          icon: Icons.payments_outlined,
        ),
      );

      expect(find.text('12,400.75'), findsOneWidget);
    });

    testWidgets('quick action tiles in a row', (tester) async {
      await _pump(
        tester,
        const Row(
          children: [
            Expanded(
              child: QuickActionTile(
                icon: Icons.point_of_sale,
                label: 'بيع جديد من الكاشير',
                accent: Color(0xFFB45309),
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: QuickActionTile(
                icon: Icons.receipt_long,
                label: 'تحصيل وتسوية الدليفري',
                accent: Color(0xFF0284C7),
              ),
            ),
          ],
        ),
      );

      expect(find.text('بيع جديد من الكاشير'), findsOneWidget);
    });

    testWidgets('feed rows with trailing', (tester) async {
      await _pump(
        tester,
        const Column(
          children: [
            FeedRow(
              tone: StatusTone.warning,
              title: 'دجاج متبل بكمية كبيرة للشواء أقل من حد إعادة الطلب',
              subtitle: 'المخزون الحالي 2 كجم · الحد 10 كجم',
              trailing: Text('دلوقتي'),
            ),
            SizedBox(height: 12),
            FeedRow(
              tone: StatusTone.negative,
              title: 'تعارض مزامنة في مدفوعات الكاش يحتاج مراجعة المدير',
            ),
          ],
        ),
      );

      expect(find.text('دلوقتي'), findsOneWidget);
    });
  });
}

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/page.dart';
import '../../core/widgets/primitives.dart';
import '../../core/widgets/rms_table.dart';
import '../../core/widgets/stat_card.dart';
import '../../core/widgets/status.dart';
import '../../core/widgets/surface_card.dart';
import '../../data/mock/mock_data.dart';
import '../common/format.dart';

class AccountingScreen extends StatelessWidget {
  const AccountingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PageBody(
      children: [
        const GridRow(children: [
          StatCard(label: 'النقدية في الدرج', value: '1,204.50 ج.م', delta: 'متوقع 1,196.00 ج.م', deltaTone: DeltaTone.positive),
          StatCard(label: 'بطاقات مسددة', value: '4,318.00 ج.م', delta: '+6.2%', deltaTone: DeltaTone.positive),
          StatCard(label: 'قيد المزامنة', value: '18.00 ج.م', delta: 'سجل واحد', deltaTone: DeltaTone.neutral),
          StatCard(label: 'استردادات اليوم', value: '-9.50 ج.م', delta: 'مراجعة واحدة', deltaTone: DeltaTone.negative),
        ]),
        const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _CashSessionCard()),
            SizedBox(width: AppSpacing.lg),
            Expanded(child: _ApprovalsPanel()),
          ],
        ),
        const _LedgerCard(),
      ],
    );
  }
}

class _CashSessionCard extends StatelessWidget {
  const _CashSessionCard();

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: 'جلسة النقدية',
            trailing: const Tag(label: 'مفتوحة', tone: StatusTone.positive),
          ),
          const SizedBox(height: 12),
          for (final (k, v) in const [
            ('الفتح', '12:00 · بواسطة أمّار'),
            ('رأس مال الفتح', '200.00 ج.م'),
            ('مبيعات نقدية', '1,004.50 ج.م'),
            ('الدرج المتوقع', '1,204.50 ج.م'),
            ('درج معدود', '— لم يُعد بعد'),
          ])
            KeyValue(label: k, value: v),
          const SizedBox(height: 12),
          const RmsButton(label: 'عدّ وإغلاق الجلسة', icon: Icons.calculate_outlined, onPressed: null, dense: false),
        ],
      ),
    );
  }
}

class _ApprovalsPanel extends StatelessWidget {
  const _ApprovalsPanel();

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'يحتاج مراجعة', subtitle: 'الإجراءات المالية تتطلب اعتمادًا'),
          const SizedBox(height: 12),
          _ApprovalRow(
            title: 'استرداد · T-018',
            subtitle: 'تضارب في النسخة مع الخادم',
            amount: '-9.50 ج.م',
            tone: StatusTone.negative,
          ),
          const SizedBox(height: 10),
          _ApprovalRow(
            title: 'تحصيل · DL-0096',
            subtitle: 'مطالبة دون اتصال، بانتظار المطابقة',
            amount: '18.00 ج.م',
            tone: StatusTone.warning,
          ),
          const SizedBox(height: 10),
          _ApprovalRow(
            title: 'تسوية · مروان ر.',
            subtitle: 'مسودة — 3 توصيلات',
            amount: '145.50 ج.م',
            tone: StatusTone.info,
          ),
        ],
      ),
    );
  }
}

class _ApprovalRow extends StatelessWidget {
  const _ApprovalRow({
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.tone,
  });

  final String title;
  final String subtitle;
  final String amount;
  final StatusTone tone;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        StatusDot(tone: tone),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppText.tableCellPrimary),
              Text(subtitle, style: AppText.caption.copyWith(fontSize: 10)),
            ],
          ),
        ),
        Text(amount, style: AppText.tableCellPrimary.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(width: 8),
        const RmsButton(label: 'مراجعة', onPressed: null),
      ],
    );
  }
}

class _LedgerCard extends StatelessWidget {
  const _LedgerCard();

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: EdgeInsets.zero,
      clip: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
            child: SectionHeader(
              title: 'سجل المعاملات',
              subtitle: 'إضافة فقط · إزالة التكرار عند المزامنة',
              trailing: RmsButton(label: 'تصدير', icon: Icons.download, onPressed: () {}),
            ),
          ),
          RmsTable(
            columns: const [
              RmsColumn('الوقت', width: 70),
              RmsColumn('النوع', flex: 2),
              RmsColumn('المرجع', flex: 3),
              RmsColumn('الطريقة', flex: 2),
              RmsColumn('المزامنة', flex: 3),
              RmsColumn('المبلغ', flex: 2, align: TextAlign.right),
            ],
            rows: [
              for (final l in MockData.ledger)
                [
                  Text(l.time, style: AppText.caption),
                  Text(l.type, style: AppText.tableCell),
                  Text(l.ref, style: AppText.tableCellPrimary),
                  Text(l.method, style: AppText.tableCell),
                  StatusText(label: syncStateView(l.sync).$1, tone: syncStateView(l.sync).$2),
                  Text(
                    money(l.amount),
                    style: AppText.tableCellPrimary.copyWith(
                      fontWeight: FontWeight.w600,
                      color: l.amount < 0 ? AppColors.negative : AppColors.fgBright,
                    ),
                  ),
                ],
            ],
          ),
        ],
      ),
    );
  }
}

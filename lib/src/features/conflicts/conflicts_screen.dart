import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/page.dart';
import '../../core/widgets/primitives.dart';
import '../../core/widgets/rms_table.dart';
import '../../core/widgets/status.dart';
import '../../core/widgets/surface_card.dart';
import '../../data/mock/mock_data.dart';

class ConflictsScreen extends StatelessWidget {
  const ConflictsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PageBody(
      children: [
        Row(
          children: [
            const SectionHeader(
              title: 'التعارضات',
              subtitle: 'تُكتشف عند المزامنة · التعارضات المالية تتطلب مراجعة',
            ),
            const Spacer(),
            const Tag(label: '2 غير محلولة', tone: StatusTone.negative),
          ],
        ),
        const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 2, child: _ConflictList()),
            SizedBox(width: AppSpacing.lg),
            Expanded(child: _StrategyCard()),
          ],
        ),
        const SurfaceCard(
          level: SurfaceLevel.secondary,
          child: Row(
            children: [
              Icon(Icons.gavel_outlined, size: 16, color: AppColors.warning),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'لا تُحل التعارضات ذات الأهمية المالية تلقائيًا بقاعدة آخر كاتب يفوز. تُحفظ نسختا الحالة للتحقيق حتى يقوم مستخدم مصرح به بالحل.',
                  style: AppText.body,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ConflictList extends StatelessWidget {
  const _ConflictList();

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: EdgeInsets.zero,
      clip: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 14, 20, 10),
            child: SectionHeader(title: 'غير محلولة'),
          ),
          for (var i = 0; i < MockData.conflicts.length; i++) ...[
            _ConflictTile(row: MockData.conflicts[i]),
            if (i != MockData.conflicts.length - 1)
              const Divider(height: 1, indent: 20, endIndent: 20, color: AppColors.borderFaint),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _ConflictTile extends StatelessWidget {
  const _ConflictTile({required this.row});

  final ConflictRow row;

  StatusTone get _tone => switch (row.severity) {
        'مالي' => StatusTone.negative,
        'إسناد' => StatusTone.warning,
        'مخزون' => StatusTone.warning,
        _ => StatusTone.neutral,
      };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          StatusDot(tone: _tone, size: 6),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(row.id, style: AppText.mono.copyWith(fontSize: 10.5)),
                    const SizedBox(width: 8),
                    Tag(label: row.severity.toUpperCase(), tone: _tone),
                  ],
                ),
                const SizedBox(height: 4),
                Text(row.entity, style: AppText.tableCellPrimary),
                Text('${row.type} · اكتُشف ${row.detectedAt}', style: AppText.caption.copyWith(fontSize: 10)),
              ],
            ),
          ),
          const RmsButton(label: 'مقارنة', onPressed: null),
          const SizedBox(width: 8),
          const RmsButton(label: 'حل', variant: BtnVariant.primary, onPressed: null),
        ],
      ),
    );
  }
}

class _StrategyCard extends StatelessWidget {
  const _StrategyCard();

  static const _strategies = [
    ('إعدادات القائمة', 'مرجعها الخادم؛ تحديث اللقطات القديمة'),
    ('إنشاء الطلب', 'إنشاء آمن بمفتاح مستقر'),
    ('أصناف الطلب', 'فحوصات النسخة والتعامل الصريح'),
    ('حالة المطبخ', 'التحقق من الانتقالات القانونية؛ الاحتفاظ بالسجل'),
    ('المدفوعات النقدية', 'إضافة فقط مع إزالة التكرار'),
    ('تحصيلات السائقين', 'إضافة فقط + مطابقة'),
    ('التسويات', 'تحقق موثوق؛ لا قاعدة آخر كاتب يفوز'),
    ('المخزون', 'حركات إضافة فقط؛ حل التعارضات'),
    ('الأدوار والصلاحيات', 'مرجعها الخادم؛ لا تعديل دون اتصال'),
  ];

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'استراتيجية الحل', subtitle: 'حسب نوع الكيان'),
          const SizedBox(height: 12),
          RmsTable(
            columns: const [
              RmsColumn('الكيان', flex: 3),
              RmsColumn('الاستراتيجية', flex: 5),
            ],
            rows: [
              for (final (entity, strategy) in _strategies)
                [
                  Text(entity, style: AppText.tableCellPrimary.copyWith(fontSize: 11)),
                  Text(strategy, style: AppText.tableCell.copyWith(fontSize: 11)),
                ],
            ],
          ),
        ],
      ),
    );
  }
}

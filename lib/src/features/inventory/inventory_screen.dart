import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/page.dart';
import '../../core/widgets/primitives.dart';
import '../../core/widgets/rms_table.dart';
import '../../core/widgets/stat_card.dart';
import '../../core/widgets/status.dart';
import '../../core/widgets/surface_card.dart';
import '../../data/mock/mock_data.dart';

class InventoryScreen extends StatelessWidget {
  const InventoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final low = MockData.inventory.where((i) => i.low).length;
    return PageBody(
      children: [
        GridRow(children: [
          const StatCard(label: 'أصناف متتبعة', value: '6'),
          StatCard(
            label: 'أقل من حد إعادة الطلب',
            value: '$low',
            delta: 'مطلوب إجراء',
            deltaTone: low > 0 ? DeltaTone.negative : DeltaTone.positive,
          ),
          const StatCard(label: 'حركات دون اتصال', value: '5', delta: 'في الطابور', deltaTone: DeltaTone.neutral),
          const StatCard(label: 'تعارضات مخزون', value: '1', delta: 'مراجعة', deltaTone: DeltaTone.negative),
        ]),
        const Row(
          children: [
            SectionHeader(
              title: 'مستويات المخزون',
              subtitle: 'الحركات تُسجّل إضافة فقط وتُحل صراحة عند المزامنة',
            ),
            Spacer(),
            RmsButton(label: 'استلام مخزون', icon: Icons.add, onPressed: null),
          ],
        ),
        SurfaceCard(
          padding: EdgeInsets.zero,
          clip: true,
          child: RmsTable(
            columns: const [
              RmsColumn('الصنف', flex: 4),
              RmsColumn('الكمية المتاحة', flex: 2),
              RmsColumn('حد إعادة الطلب', flex: 2),
              RmsColumn('الحالة', flex: 3),
              RmsColumn('', flex: 2),
            ],
            rows: [
              for (final i in MockData.inventory)
                [
                  Text(i.item, style: AppText.tableCellPrimary),
                  Text('${i.onHand} ${i.unit}',
                      style: AppText.tableCellPrimary.copyWith(fontWeight: FontWeight.w600)),
                  Text('${i.reorderAt} ${i.unit}', style: AppText.tableCell),
                  StatusText(
                    label: i.low ? 'أقل من حد إعادة الطلب' : 'سليم',
                    tone: i.low ? StatusTone.warning : StatusTone.positive,
                  ),
                  const RmsButton(label: 'نقل', onPressed: null),
                ],
            ],
          ),
        ),
        const SurfaceCard(
          level: SurfaceLevel.secondary,
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded, size: 16, color: AppColors.warning),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'تُعلَّم حركات المخزون المتزامنة من أجهزة معزولة كتعارضات وتتطلب حلاً صريحًا — لا حلّ تلقائي أبدًا.',
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

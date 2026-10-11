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

class DeliveryScreen extends StatelessWidget {
  const DeliveryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PageBody(
      children: [
        const GridRow(children: [
          StatCard(label: 'توصيلات نشطة', value: '4', delta: '1 دون اتصال'),
          StatCard(label: 'بانتظار الإسناد', value: '1', deltaTone: DeltaTone.neutral, delta: '—'),
          StatCard(label: 'تحصيلات دون اتصال', value: '213.50 ج.م', delta: 'تسوية معلقة', deltaTone: DeltaTone.neutral),
          StatCard(label: 'متوسط وقت التوصيل', value: '28د', delta: '-3د', deltaTone: DeltaTone.positive),
        ]),
        const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 2, child: _DeliveryTable()),
            SizedBox(width: AppSpacing.lg),
            Expanded(child: _DriversPanel()),
          ],
        ),
        const _OfflineCollectionNotice(),
      ],
    );
  }
}

class _DeliveryTable extends StatelessWidget {
  const _DeliveryTable();

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
              title: 'التوصيلات',
              trailing: RmsButton(label: 'إسناد التالي', icon: Icons.bolt, onPressed: () {}),
            ),
          ),
          RmsTable(
            columns: const [
              RmsColumn('المهمة', flex: 2),
              RmsColumn('الطلب', flex: 2),
              RmsColumn('السائق', flex: 2),
              RmsColumn('العنوان', flex: 4),
              RmsColumn('الحالة', flex: 3),
              RmsColumn('المبلغ', flex: 2, align: TextAlign.right),
            ],
            rows: [
              for (final d in MockData.deliveries)
                [
                  Text(d.id, style: AppText.tableCellPrimary),
                  Text(d.orderRef, style: AppText.tableCell),
                  Text(d.driver, style: AppText.tableCell),
                  Text(d.address, style: AppText.tableCell, overflow: TextOverflow.ellipsis),
                  Row(
                    children: [
                      StatusDot(
                        tone: d.offline ? StatusTone.warning : StatusTone.info,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(d.state, style: AppText.tableCell, overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                  Text(money(d.amount),
                      style: AppText.tableCellPrimary.copyWith(fontWeight: FontWeight.w600)),
                ],
            ],
          ),
        ],
      ),
    );
  }
}

class _DriversPanel extends StatelessWidget {
  const _DriversPanel();

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'السائقون', subtitle: 'الوردية · 12:00–20:00'),
          const SizedBox(height: 12),
          for (final d in MockData.drivers) ...[
            Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: const BoxDecoration(color: AppColors.hover, shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: Text(d.name.substring(0, 1), style: AppText.caption),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(d.name, style: AppText.tableCellPrimary),
                      Text('${d.active} نشطة', style: AppText.caption.copyWith(fontSize: 10)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(money(d.collected),
                        style: AppText.tableCellPrimary.copyWith(fontWeight: FontWeight.w600)),
                    Text(d.status, style: AppText.caption.copyWith(fontSize: 10)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          const Divider(height: 20, color: AppColors.borderSubtle),
          Row(
            children: [
              Text('قائمة تسوية التحصيلات المعلقة', style: AppText.bodyStrong.copyWith(fontSize: 12)),
              const Spacer(),
              const Tag(label: '3 مسودات', tone: StatusTone.warning),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'لا يمكن إنهاء تحصيلات المسجلة محليًا بدون تحقق من الخادم.',
            style: AppText.caption,
          ),
          const SizedBox(height: 12),
          const RmsButton(label: 'فتح قائمة التسوية', icon: Icons.arrow_forward, onPressed: null, dense: false),
        ],
      ),
    );
  }
}

class _OfflineCollectionNotice extends StatelessWidget {
  const _OfflineCollectionNotice();

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      level: SurfaceLevel.secondary,
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 16, color: AppColors.info),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: AppText.body,
                children: const [
                  TextSpan(text: 'التحصيل المسجل محليًا هو مطالبة وليس دليلاً على الاستلام. '),
                  TextSpan(
                    text: 'المطابقة واعتماد التسوية يتطلبان تحققًا من الخادم.',
                    style: TextStyle(color: AppColors.fgBright, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          const StatusText(label: 'مطابقة معلقة', tone: StatusTone.warning),
        ],
      ),
    );
  }
}

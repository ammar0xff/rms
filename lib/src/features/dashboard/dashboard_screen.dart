import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/charts.dart';
import '../../core/widgets/page.dart';
import '../../core/widgets/primitives.dart';
import '../../core/widgets/rms_table.dart';
import '../../core/widgets/stat_card.dart';
import '../../core/widgets/status.dart';
import '../../core/widgets/surface_card.dart';
import '../../core/widgets/sync_chip.dart';
import '../../data/mock/mock_data.dart';
import '../common/format.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PageBody(
      children: [
        const HeroKpi(
          label: 'صافي مبيعات اليوم',
          value: '8,412.50 ج.م',
          delta: '+12.4%',
          deltaTone: DeltaTone.positive,
          subtext: 'مقارنة بمتوسط 14 يومًا',
          spark: MockData.salesTrend,
        ),
        const GridRow(children: [
          StatCard(label: 'الطلبات', value: '312', delta: '+8.1%'),
          StatCard(label: 'متوسط الفاتورة', value: '26.96 ج.م', delta: '+2.3%'),
          StatCard(label: 'عمليات دون اتصال اليوم', value: '37', delta: '24 قيد الانتظار', deltaTone: DeltaTone.neutral),
        ]),
        const _SalesCard(),
        const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 2, child: _RecentOrders()),
            SizedBox(width: AppSpacing.lg),
            Expanded(child: _AlertsPanel()),
          ],
        ),
        const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 2, child: _SyncHealthCard()),
            SizedBox(width: AppSpacing.lg),
            Expanded(child: _BranchCard()),
          ],
        ),
      ],
    );
  }
}

class _SalesCard extends StatelessWidget {
  const _SalesCard();

  static const _hours = [
    '10ص', '11ص', '12م', '1م', '2م', '3م', '4م', '5م', '6م', '7م', '8م', '9م',
  ];

  static String _fmtTick(double v) {
    if (v >= 1000) {
      final k = v / 1000;
      return '${k.toStringAsFixed(k == k.roundToDouble() ? 0 : 1)}k';
    }
    return v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);
  }

  static String _peakTime(int index) {
    final h = 10 + index;
    final amPm = h < 12 ? 'ص' : 'م';
    final h12 = h == 12 ? 12 : h % 12;
    return '$h12:00 $amPm';
  }

  @override
  Widget build(BuildContext context) {
    final data = MockData.hourlySales;
    final rawMax = data.isEmpty ? 1.0 : data.reduce((a, b) => a > b ? a : b);
    final top = ((rawMax / 5).ceil() * 5).toDouble();
    final ticks = <double>[top, top / 2, (top / 4).roundToDouble(), 0];
    var peak = 0;
    for (var i = 0; i < data.length; i++) {
      if (data[i] > data[peak]) peak = i;
    }

    return SurfaceCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: SectionHeader(
              title: 'المبيعات بالساعة',
              subtitle: 'اليوم · آخر تحديث 12:45',
              trailing: const Tag(label: 'مباشر', tone: StatusTone.positive),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: SizedBox(
              height: 160,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  SizedBox(
                    width: 42,
                    height: 160,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final v in ticks)
                          Text(_fmtTick(v), style: AppText.caption.copyWith(fontSize: 9)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: MiniBars(
                      values: data,
                      height: 160,
                      highlightIndex: peak,
                      color: AppColors.brand,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 62, right: 20, top: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final d in _hours) Text(d, style: AppText.caption.copyWith(fontSize: 9)),
              ],
            ),
          ),
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.borderSubtle)),
            ),
            child: Row(
              children: [
                _FooterStat(label: 'ساعة الذروة', value: _peakTime(peak)),
                const _VDivider(),
                _FooterStat(label: 'الطلبات', value: '312'),
                const _VDivider(),
                _FooterStat(label: 'داخل الصالة / توصيل', value: '198 / 74'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FooterStat extends StatelessWidget {
  const _FooterStat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Row(
        children: [
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: AppText.caption)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              style: AppText.caption.copyWith(color: AppColors.fgSecondary, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

class _VDivider extends StatelessWidget {
  const _VDivider();
  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 12, color: AppColors.borderStrong);
}

class _RecentOrders extends StatelessWidget {
  const _RecentOrders();

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
              title: 'آخر الطلبات',
              trailing: RmsButton(label: 'عرض الكل', variant: BtnVariant.ghost, onPressed: () {}),
            ),
          ),
          RmsTable(
            columns: const [
              RmsColumn('الطلب', flex: 3),
              RmsColumn('النوع', flex: 2),
              RmsColumn('الحالة', flex: 3),
              RmsColumn('المزامنة', flex: 3),
              RmsColumn('الإجمالي', flex: 2, align: TextAlign.right),
            ],
            rows: [
              for (final o in MockData.orders)
                [
                  Row(
                    children: [
                      Flexible(
                        child: Text(o.number, overflow: TextOverflow.ellipsis, style: AppText.tableCellPrimary),
                      ),
                      if (o.provisional) ...[
                        const SizedBox(width: 6),
                        const Tag(label: 'مؤقت', tone: StatusTone.neutral),
                      ],
                    ],
                  ),
                  Text(o.type, style: AppText.tableCell),
                  Text(o.status, style: AppText.tableCell),
                  StatusText(label: syncStateView(o.sync).$1, tone: syncStateView(o.sync).$2),
                  Text(money(o.total), style: AppText.tableCellPrimary.copyWith(fontWeight: FontWeight.w600)),
                ],
            ],
          ),
        ],
      ),
    );
  }
}

class _AlertsPanel extends StatelessWidget {
  const _AlertsPanel();

  @override
  Widget build(BuildContext context) {
    final lowStock = MockData.inventory.where((i) => i.low).toList();
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'التنبيهات'),
          const SizedBox(height: 12),
          for (final item in lowStock) ...[
            Row(
              children: [
                const StatusDot(tone: StatusTone.warning),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('${item.item} أقل من حد إعادة الطلب', style: AppText.tableCellPrimary),
                ),
                Text('${item.onHand}${item.unit}', style: AppText.caption),
              ],
            ),
            const SizedBox(height: 10),
          ],
          const Divider(height: 20, color: AppColors.borderSubtle),
          Row(
            children: [
              const StatusDot(tone: StatusTone.negative),
              const SizedBox(width: 8),
              Expanded(child: Text('2 تعارضات غير محلولة', style: AppText.tableCellPrimary)),
              const Icon(Icons.chevron_right, size: 14, color: AppColors.fgGhost),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const StatusDot(tone: StatusTone.info),
              const SizedBox(width: 8),
              Expanded(child: Text('مزامنة القائمة: حديثة', style: AppText.tableCellPrimary)),
              Text('قبل دقيقتين', style: AppText.caption),
            ],
          ),
        ],
      ),
    );
  }
}

class _SyncHealthCard extends StatelessWidget {
  const _SyncHealthCard();

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: 'صحة المزامنة',
            trailing: const SyncChip(),
          ),
          const SizedBox(height: 14),
          const SyncStatRow(),
          const SizedBox(height: 14),
          ProgressBar(value: 0.86, color: AppColors.positive),
          const SizedBox(height: 8),
          Text(
            'تمت مزامنة 86% من عمليات اليوم. العمل دون اتصال — 24 عملية في طابور محلي.',
            style: AppText.caption,
          ),
        ],
      ),
    );
  }
}

class _BranchCard extends StatelessWidget {
  const _BranchCard();

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'حالة الفرع'),
          const SizedBox(height: 12),
          for (final (k, v) in const [
            ('تقرير الكاشير (Z)', 'مفتوح · 12:00'),
            ('درج النقدية', '1,204.50 ج.م'),
            ('الموظفون النشطون', '9 في الوردية'),
            ('إصدار التطبيق', '0.9.4 (build 812)'),
            ('إصدار المخطط', 'v7'),
          ])
            KeyValue(label: k, value: v),
        ],
      ),
    );
  }
}
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
          label: 'Net sales today',
          value: '\$8,412.50',
          delta: '+12.4%',
          deltaTone: DeltaTone.positive,
          subtext: 'vs 14-day average',
          spark: MockData.salesTrend,
        ),
        const GridRow(children: [
          StatCard(label: 'Orders', value: '312', delta: '+8.1%'),
          StatCard(label: 'Avg ticket', value: '\$26.96', delta: '+2.3%'),
          StatCard(label: 'Offline ops today', value: '37', delta: '24 pending', deltaTone: DeltaTone.neutral),
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
    '10a', '11a', '12p', '1p', '2p', '3p', '4p', '5p', '6p', '7p', '8p', '9p',
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
    final amPm = h < 12 ? 'AM' : 'PM';
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
              title: 'Sales by hour',
              subtitle: 'Today · updated 12:45',
              trailing: const Tag(label: 'LIVE', tone: StatusTone.positive),
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
                _FooterStat(label: 'Peak hour', value: _peakTime(peak)),
                const _VDivider(),
                _FooterStat(label: 'Orders', value: '312'),
                const _VDivider(),
                _FooterStat(label: 'Dine-in / Delivery', value: '198 / 74'),
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
              title: 'Recent orders',
              trailing: RmsButton(label: 'View all', variant: BtnVariant.ghost, onPressed: () {}),
            ),
          ),
          RmsTable(
            columns: const [
              RmsColumn('Order', flex: 3),
              RmsColumn('Type', flex: 2),
              RmsColumn('Status', flex: 3),
              RmsColumn('Sync', flex: 3),
              RmsColumn('Total', flex: 2, align: TextAlign.right),
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
                        const Tag(label: 'PROV', tone: StatusTone.neutral),
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
          const SectionHeader(title: 'Alerts'),
          const SizedBox(height: 12),
          for (final item in lowStock) ...[
            Row(
              children: [
                const StatusDot(tone: StatusTone.warning),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('${item.item} below reorder', style: AppText.tableCellPrimary),
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
              Expanded(child: Text('2 unresolved conflicts', style: AppText.tableCellPrimary)),
              const Icon(Icons.chevron_right, size: 14, color: AppColors.fgGhost),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const StatusDot(tone: StatusTone.info),
              const SizedBox(width: 8),
              Expanded(child: Text('Menu sync: fresh', style: AppText.tableCellPrimary)),
              Text('2m ago', style: AppText.caption),
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
            title: 'Sync health',
            trailing: const SyncChip(),
          ),
          const SizedBox(height: 14),
          const SyncStatRow(),
          const SizedBox(height: 14),
          ProgressBar(value: 0.86, color: AppColors.positive),
          const SizedBox(height: 8),
          Text(
            '86% of today\'s operations synced. Working offline — 24 queued locally.',
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
          const SectionHeader(title: 'Branch status'),
          const SizedBox(height: 12),
          for (final (k, v) in const [
            ('Register Z-Report', 'Open · 12:00'),
            ('Cash drawer', '\$1,204.50'),
            ('Active staff', '9 on shift'),
            ('App version', '0.9.4 (build 812)'),
            ('Schema version', 'v7'),
          ])
            KeyValue(label: k, value: v),
        ],
      ),
    );
  }
}

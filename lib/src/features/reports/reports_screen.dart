import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/charts.dart';
import '../../core/widgets/page.dart';
import '../../core/widgets/primitives.dart';
import '../../core/widgets/stat_card.dart';
import '../../core/widgets/status.dart';
import '../../core/widgets/surface_card.dart';

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PageBody(
      children: [
        Row(
          children: [
            const SectionHeader(
              title: 'Reports',
              subtitle: 'Refreshed from authoritative aggregates on sync',
            ),
            const Spacer(),
            const StatusText(label: 'Data as of 12:45 · last sync 2m ago', tone: StatusTone.positive),
            const SizedBox(width: 12),
            RmsButton(label: 'Export CSV', icon: Icons.download, onPressed: () {}),
          ],
        ),
        const HeroKpi(
          label: 'Gross sales this week',
          value: '\$42,980',
          delta: '+9.8%',
          subtext: 'vs previous week',
          spark: <double>[620, 700, 660, 810, 760, 880, 940, 870, 1020, 990, 1080, 1150],
        ),
        const GridRow(children: [
          StatCard(label: 'Orders', value: '1,842', delta: '+5.4%'),
          StatCard(label: 'Avg ticket', value: '\$23.33', delta: '+1.9%'),
          StatCard(label: 'Delivery share', value: '31%', delta: '+2.1%'),
          StatCard(label: 'Repeat rate', value: '48%', delta: '+0.8%'),
        ]),
        const _TrendCard(),
        const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _CategoryCard()),
            SizedBox(width: AppSpacing.lg),
            Expanded(child: _PaymentMixCard()),
          ],
        ),
      ],
    );
  }
}

class _TrendCard extends StatelessWidget {
  const _TrendCard();

  @override
  Widget build(BuildContext context) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return SurfaceCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: const SectionHeader(title: 'Sales trend', subtitle: 'Last 7 days'),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: SizedBox(
              height: 180,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  SizedBox(
                    width: 44,
                    height: 180,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final v in ['8k', '6k', '4k', '2k', '0'])
                          Text(v, style: AppText.caption.copyWith(fontSize: 9)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: MiniBars(
                      values: const <double>[5480, 6100, 5920, 6740, 8120, 9860, 7760],
                      height: 180,
                      highlightIndex: 5,
                      color: AppColors.brand,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 64, right: 20, top: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final d in days) Text(d, style: AppText.caption.copyWith(fontSize: 9)),
              ],
            ),
          ),
          Container(
            margin: const EdgeInsets.only(top: 14),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.borderSubtle)),
            ),
            child: Row(
              children: const [
                _FooterStat(label: 'Best day', value: 'Saturday'),
                _VDivider(),
                _FooterStat(label: 'Weekly total', value: '\$42,980'),
                _VDivider(),
                _FooterStat(label: 'Avg / day', value: '\$6,140'),
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
          Text(label, style: AppText.caption),
          const SizedBox(width: 6),
          Text(value, style: AppText.caption.copyWith(color: AppColors.fgSecondary, fontWeight: FontWeight.w500)),
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

class _CategoryCard extends StatelessWidget {
  const _CategoryCard();

  @override
  Widget build(BuildContext context) {
    const data = [
      ('Pizza', 0.34, AppColors.brand),
      ('Pasta', 0.24, AppColors.info),
      ('Sides', 0.18, AppColors.positive),
      ('Salads', 0.12, AppColors.purple),
      ('Drinks', 0.12, AppColors.warning),
    ];
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'Sales by category'),
          const SizedBox(height: 16),
          for (final (name, value, color) in data) ...[
            Row(
              children: [
                Expanded(child: Text(name, style: AppText.tableCell.copyWith(color: AppColors.fgSecondary))),
                Text('${(value * 100).round()}%',
                    style: AppText.tableCellPrimary.copyWith(fontFeatures: null)),
              ],
            ),
            const SizedBox(height: 6),
            ProgressBar(value: value, color: color),
            const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }
}

class _PaymentMixCard extends StatelessWidget {
  const _PaymentMixCard();

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'Payment mix'),
          const SizedBox(height: 16),
          const _MixRow(label: 'Card', value: '\$26,648', pct: '62%', color: AppColors.info),
          const _MixRow(label: 'Cash', value: '\$13,324', pct: '31%', color: AppColors.positive),
          const _MixRow(label: 'Online / other', value: '\$3,008', pct: '7%', color: AppColors.purple),
          const Divider(height: 24, color: AppColors.borderSubtle),
          Row(
            children: [
              const StatusDot(tone: StatusTone.warning),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Offline cash pending settlement', style: AppText.tableCell),
              ),
              Text('\$213.50', style: AppText.tableCellPrimary.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }
}

class _MixRow extends StatelessWidget {
  const _MixRow({required this.label, required this.value, required this.pct, required this.color});

  final String label;
  final String value;
  final String pct;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: AppText.tableCell.copyWith(color: AppColors.fgSecondary))),
          Text(value, style: AppText.tableCellPrimary),
          const SizedBox(width: 14),
          SizedBox(
            width: 34,
            child: Text(pct, textAlign: TextAlign.right, style: AppText.caption),
          ),
        ],
      ),
    );
  }
}

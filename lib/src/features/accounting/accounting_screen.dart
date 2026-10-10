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
          StatCard(label: 'Cash in drawer', value: '\$1,204.50', delta: 'expected \$1,196.00', deltaTone: DeltaTone.positive),
          StatCard(label: 'Card settled', value: '\$4,318.00', delta: '+6.2%', deltaTone: DeltaTone.positive),
          StatCard(label: 'Pending sync', value: '\$18.00', delta: '1 record', deltaTone: DeltaTone.neutral),
          StatCard(label: 'Refunds today', value: '-\$9.50', delta: '1 review', deltaTone: DeltaTone.negative),
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
            title: 'Cash session',
            trailing: const Tag(label: 'OPEN', tone: StatusTone.positive),
          ),
          const SizedBox(height: 12),
          for (final (k, v) in const [
            ('Opened', '12:00 · by Ammar'),
            ('Opening float', '\$200.00'),
            ('Cash sales', '\$1,004.50'),
            ('Expected drawer', '\$1,204.50'),
            ('Counted drawer', '— not yet counted'),
          ])
            KeyValue(label: k, value: v),
          const SizedBox(height: 12),
          const RmsButton(label: 'Count & close session', icon: Icons.calculate_outlined, onPressed: null, dense: false),
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
          const SectionHeader(title: 'Needs review', subtitle: 'Financial actions require approval'),
          const SizedBox(height: 12),
          _ApprovalRow(
            title: 'Refund · T-018',
            subtitle: 'Revision mismatch with server',
            amount: '-\$9.50',
            tone: StatusTone.negative,
          ),
          const SizedBox(height: 10),
          _ApprovalRow(
            title: 'Collection · DL-0096',
            subtitle: 'Offline claim, awaiting reconciliation',
            amount: '\$18.00',
            tone: StatusTone.warning,
          ),
          const SizedBox(height: 10),
          _ApprovalRow(
            title: 'Settlement · Marco R.',
            subtitle: 'Draft — 3 deliveries',
            amount: '\$145.50',
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
        const RmsButton(label: 'Review', onPressed: null),
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
              title: 'Transaction ledger',
              subtitle: 'Append-only · deduplicated on sync',
              trailing: RmsButton(label: 'Export', icon: Icons.download, onPressed: () {}),
            ),
          ),
          RmsTable(
            columns: const [
              RmsColumn('Time', width: 70),
              RmsColumn('Type', flex: 2),
              RmsColumn('Reference', flex: 3),
              RmsColumn('Method', flex: 2),
              RmsColumn('Sync', flex: 3),
              RmsColumn('Amount', flex: 2, align: TextAlign.right),
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

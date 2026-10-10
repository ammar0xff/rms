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
              title: 'Conflicts',
              subtitle: 'Detected on sync · financial conflicts require review',
            ),
            const Spacer(),
            const Tag(label: '2 UNRESOLVED', tone: StatusTone.negative),
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
                  'Financially significant conflicts are never resolved automatically with last-write-wins. Both snapshots are preserved for investigation until an authorized user resolves them.',
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
            child: SectionHeader(title: 'Unresolved'),
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
        'Financial' => StatusTone.negative,
        'Assignment' => StatusTone.warning,
        'Stock' => StatusTone.warning,
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
                Text('${row.type} · detected ${row.detectedAt}', style: AppText.caption.copyWith(fontSize: 10)),
              ],
            ),
          ),
          const RmsButton(label: 'Compare', onPressed: null),
          const SizedBox(width: 8),
          const RmsButton(label: 'Resolve', variant: BtnVariant.primary, onPressed: null),
        ],
      ),
    );
  }
}

class _StrategyCard extends StatelessWidget {
  const _StrategyCard();

  static const _strategies = [
    ('Menu configuration', 'Server-authoritative; refresh stale snapshots'),
    ('Order creation', 'Idempotent creation using stable ID'),
    ('Order items', 'Revision checks and explicit handling'),
    ('Kitchen status', 'Validate legal transitions; keep history'),
    ('Cash payments', 'Append-only with deduplication'),
    ('Driver collections', 'Append-only + reconciliation'),
    ('Settlements', 'Trusted validation; never last-write-wins'),
    ('Inventory', 'Append-only movements; resolve conflicts'),
    ('Roles & permissions', 'Server-authoritative; no offline mutation'),
  ];

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'Resolution strategy', subtitle: 'Per entity type'),
          const SizedBox(height: 12),
          RmsTable(
            columns: const [
              RmsColumn('Entity', flex: 3),
              RmsColumn('Strategy', flex: 5),
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

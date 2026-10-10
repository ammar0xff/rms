import 'package:flutter/material.dart';

import '../../core/state/sync_monitor.dart';
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

(String, StatusTone) _opStatus(String s) => switch (s) {
      'pending' => ('Pending', StatusTone.warning),
      'in_progress' => ('In progress', StatusTone.info),
      'synced' => ('Synced', StatusTone.positive),
      'conflict' => ('Conflict', StatusTone.negative),
      'retryable_failure' => ('Retryable', StatusTone.warning),
      'requires_user_action' => ('Needs action', StatusTone.negative),
      _ => (s, StatusTone.neutral),
    };

class SyncCenterScreen extends StatelessWidget {
  const SyncCenterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PageBody(
      children: [
        Row(
          children: [
            const SectionHeader(
              title: 'Synchronization center',
              subtitle: 'Outbox · dependency-ordered · idempotent retries',
            ),
            const Spacer(),
            const RmsButton(label: 'Reconnect & sync now', icon: Icons.sync, onPressed: null, dense: false),
          ],
        ),
        AnimatedBuilder(
          animation: SyncMonitor.instance,
          builder: (context, _) {
            final m = SyncMonitor.instance;
            return GridRow(children: [
              StatCard(label: 'Pending', value: '${m.pending}', tone: AppColors.fgBright),
              const StatCard(label: 'In progress', value: '1', delta: 'submitting'),
              StatCard(
                label: 'Failed',
                value: '${m.failed}',
                delta: 'retryable',
                deltaTone: DeltaTone.negative,
                tone: m.failed > 0 ? AppColors.negative : null,
              ),
              StatCard(
                label: 'Conflicts',
                value: '${m.conflicts}',
                delta: 'review',
                deltaTone: DeltaTone.negative,
                tone: m.conflicts > 0 ? AppColors.warning : null,
              ),
            ]);
          },
        ),
        const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 2, child: _OutboxTable()),
            SizedBox(width: AppSpacing.lg),
            Expanded(child: _SequenceCard()),
          ],
        ),
        const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _PolicyCard(
              title: 'Idempotency',
              icon: Icons.fingerprint,
              body: 'Every command carries a stable idempotency key. The backend persists operation receipts and returns the existing result for duplicates — applied to orders, payments, refunds, tickets, assignments, collections, settlements and inventory.',
            )),
            SizedBox(width: AppSpacing.lg),
            Expanded(child: _PolicyCard(
              title: 'Retry policy',
              icon: Icons.replay,
              body: 'Transient failures retry with exponential backoff and jitter. Permanent errors are not retried indefinitely, and blocked operations stay visible with actionable reasons instead of being discarded.',
            )),
          ],
        ),
      ],
    );
  }
}

class _OutboxTable extends StatelessWidget {
  const _OutboxTable();

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
              title: 'Outbox operations',
              trailing: const StatusText(label: 'processing', tone: StatusTone.info),
            ),
          ),
          RmsTable(
            columns: const [
              RmsColumn('Operation', flex: 2),
              RmsColumn('Entity', flex: 3),
              RmsColumn('Type', flex: 3),
              RmsColumn('Attempts', flex: 2, align: TextAlign.right),
              RmsColumn('Status', flex: 3),
            ],
            rows: [
              for (final op in MockData.syncOperations)
                [
                  Text(op.operationId, style: AppText.mono.copyWith(fontSize: 10.5)),
                  Text(op.entity, style: AppText.tableCell),
                  Text(op.type, style: AppText.tableCell),
                  Text('${op.attempts}', style: AppText.tableCell),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      StatusText(label: _opStatus(op.status).$1, tone: _opStatus(op.status).$2),
                      if (op.lastError != null)
                        Text(op.lastError!, style: AppText.caption.copyWith(fontSize: 9.5, color: AppColors.fgGhost)),
                    ],
                  ),
                ],
            ],
          ),
        ],
      ),
    );
  }
}

class _SequenceCard extends StatelessWidget {
  const _SequenceCard();

  static const _steps = [
    'Create customer if needed',
    'Submit order',
    'Synchronize payment records',
    'Synchronize kitchen events',
    'Synchronize delivery assignment / status',
    'Synchronize eligible collection records',
    'Refresh server-confirmed summaries',
  ];

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'Sync order', subtitle: 'Respected dependencies'),
          const SizedBox(height: 14),
          for (var i = 0; i < _steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 18,
                    height: 18,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceSunken,
                      border: Border.all(color: AppColors.borderStrong),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('${i + 1}', style: AppText.caption.copyWith(fontSize: 9)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(_steps[i], style: AppText.tableCell.copyWith(color: AppColors.fgSecondary))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _PolicyCard extends StatelessWidget {
  const _PolicyCard({required this.title, required this.icon, required this.body});

  final String title;
  final IconData icon;
  final String body;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: AppColors.fgMuted),
              const SizedBox(width: 8),
              Text(title, style: AppText.sectionHeading),
            ],
          ),
          const SizedBox(height: 10),
          Text(body, style: AppText.body),
        ],
      ),
    );
  }
}

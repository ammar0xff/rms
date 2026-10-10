import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/page.dart';
import '../../core/widgets/primitives.dart';
import '../../core/widgets/status.dart';
import '../../core/widgets/surface_card.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PageBody(
      children: [
        const SectionHeader(
          title: 'Settings & system',
          subtitle: 'Version visibility, upgrades, flags and offline policy',
        ),
        const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _VersionCard()),
            SizedBox(width: AppSpacing.lg),
            Expanded(child: _UpdateCard()),
          ],
        ),
        const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _MigrationCard()),
            SizedBox(width: AppSpacing.lg),
            Expanded(child: _OfflinePolicyCard()),
          ],
        ),
        const _FlagsCard(),
      ],
    );
  }
}

class _VersionCard extends StatelessWidget {
  const _VersionCard();

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'Version visibility', subtitle: 'Authorized admins only'),
          const SizedBox(height: 12),
          for (final (k, v) in const [
            ('App version', '0.9.4 · build 812'),
            ('Local schema', 'v7'),
            ('API contract', '2024-09-01'),
            ('Backend release', '2024.10.2'),
            ('Cloud data schema', 'v12'),
            ('Configuration', 'v24'),
            ('Device ID', 'dev_a81f…c3'),
          ])
            KeyValue(label: k, value: v, mono: true),
        ],
      ),
    );
  }
}

class _UpdateCard extends StatelessWidget {
  const _UpdateCard();

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: 'Updates',
            trailing: const Tag(label: 'STABLE', tone: StatusTone.positive),
          ),
          const SizedBox(height: 12),
          for (final (k, v) in const [
            ('Release channel', 'stable'),
            ('Current version', '0.9.4'),
            ('Minimum supported', '0.9.0'),
            ('Last release check', '12:40'),
            ('Rollout cohort', '25%'),
          ])
            KeyValue(label: k, value: v),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.info.withValues(alpha: 0.06),
              border: Border.all(color: AppColors.info.withValues(alpha: 0.2)),
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.system_update_alt, size: 15, color: AppColors.info),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Optional update available · 0.9.5',
                          style: AppText.tableCellPrimary.copyWith(color: AppColors.info)),
                      const SizedBox(height: 3),
                      Text(
                        'Deferral allowed. Pending local transactions are preserved and migrations run transactionally.',
                        style: AppText.caption.copyWith(fontSize: 10.5),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                const RmsButton(label: 'Update', variant: BtnVariant.primary, onPressed: null),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MigrationCard extends StatelessWidget {
  const _MigrationCard();

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: 'Local migration',
            trailing: const StatusText(label: 'Complete', tone: StatusTone.positive),
          ),
          const SizedBox(height: 12),
          for (final (k, v) in const [
            ('Status', 'v6 → v7 applied'),
            ('Completed', '2024-10-08 09:14'),
            ('Outbox preserved', 'Yes — 0 dropped'),
            ('Checkpoints', 'intact'),
            ('Rollback copy', 'retained'),
          ])
            KeyValue(label: k, value: v),
          const SizedBox(height: 12),
          Text(
            'Migrations run before the new schema is accessed, preserve outbox entries and idempotency keys, and only advance the version on success.',
            style: AppText.caption,
          ),
        ],
      ),
    );
  }
}

class _OfflinePolicyCard extends StatelessWidget {
  const _OfflinePolicyCard();

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'Offline policy'),
          const SizedBox(height: 12),
          for (final (k, v) in const [
            ('Allowed offline duration', '24h'),
            ('Menu cache max age', '12h'),
            ('Stale-policy behavior', 'Warn cashier'),
            ('High-risk ops offline', 'Blocked'),
            ('Print reprint on reconnect', 'Manual only'),
          ])
            KeyValue(label: k, value: v),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surfaceSunken,
              border: Border.all(color: AppColors.borderStrong),
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: Text(
              'A disconnected device cannot know a mandatory update exists. The last valid release policy is cached, its age tracked, and unsynchronized records are never discarded.',
              style: AppText.caption.copyWith(fontSize: 10.5, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _FlagsCard extends StatelessWidget {
  const _FlagsCard();

  static const _flags = [
    ('New POS layout', 'Global · on', true),
    ('Auto delivery assignment', 'Cohort 25%', false),
    ('Settlement workflow v2', 'Branch · off', false),
    ('Ticket format compact', 'Role · kitchen', true),
    ('Inventory engine v2', 'Global · off', false),
  ];

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: EdgeInsets.zero,
      clip: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 14, 20, 4),
            child: SectionHeader(
              title: 'Feature flags',
              subtitle: 'Server-managed · never a replacement for backend authorization',
            ),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < _flags.length; i++) ...[
            _FlagRow(name: _flags[i].$1, scope: _flags[i].$2, on: _flags[i].$3),
            if (i != _flags.length - 1)
              const Divider(height: 1, indent: 20, endIndent: 20, color: AppColors.borderFaint),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _FlagRow extends StatelessWidget {
  const _FlagRow({required this.name, required this.scope, required this.on});

  final String name;
  final String scope;
  final bool on;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: AppText.tableCellPrimary),
                Text(scope, style: AppText.caption.copyWith(fontSize: 10)),
              ],
            ),
          ),
          Container(
            width: 34,
            height: 18,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: on ? AppColors.brandSoft : AppColors.surfaceSunken,
              border: Border.all(color: on ? AppColors.brandLine : AppColors.borderStrong),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Align(
              alignment: on ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: on ? AppColors.brand : AppColors.fgGhost,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

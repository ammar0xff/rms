import 'package:flutter/material.dart';

import '../../domain/models/app_role.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text.dart';
import 'status.dart';

/// Shared building blocks for the five role homes.
///
/// Every role gets the same blocks with its own accent — the screens feel
/// like uniforms, not separate apps. All blocks are phone-safe by
/// construction: titles flex with ellipsis, actions go full-width, and rows
/// wrap instead of overflowing.
Color roleAccent(AppRole role) => switch (role) {
      AppRole.cashier => AppColors.cashierAccent,
      AppRole.chef => AppColors.chefAccent,
      AppRole.driver => AppColors.driverAccent,
      AppRole.manager => AppColors.managerAccent,
      AppRole.developer => AppColors.developerAccent,
    };

/// The top of a role home: who/where you are, the one number that matters,
/// and the one action you'll take next.
class RoleHero extends StatelessWidget {
  const RoleHero({
    super.key,
    required this.role,
    required this.kicker,
    required this.title,
    this.subtitle,
    this.value,
    this.valueLabel,
    this.action,
  });

  final AppRole role;
  final String kicker;
  final String title;
  final String? subtitle;
  final String? value;
  final String? valueLabel;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final accent = roleAccent(role);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            accent.withValues(alpha: 0.14),
            accent.withValues(alpha: 0.03),
          ],
        ),
        color: AppColors.surface,
        border: Border.all(color: accent.withValues(alpha: 0.25)),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg + 7),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      kicker,
                      style: AppText.label.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(title, style: AppText.h1),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(subtitle!, style: AppText.body),
                    ],
                  ],
                ),
              ),
              if (value != null) ...[
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      value!,
                      style: AppText.hero.copyWith(
                        fontSize: 32,
                        color: AppColors.fg,
                      ),
                    ),
                    if (valueLabel != null)
                      Text(valueLabel!, style: AppText.caption),
                  ],
                ),
              ],
            ],
          ),
          if (action != null) ...[
            const SizedBox(height: 12),
            action!,
          ],
        ],
      ),
    );
  }
}

/// One KPI: label on top, big tabular number, optional delta chip.
class KpiCard extends StatelessWidget {
  const KpiCard({
    super.key,
    required this.label,
    required this.value,
    this.delta,
    this.deltaGood,
    this.icon,
    this.accent,
  });

  final String label;
  final String value;
  final String? delta;
  final bool? deltaGood;
  final IconData? icon;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final tone = deltaGood == null
        ? StatusTone.neutral
        : (deltaGood! ? StatusTone.positive : StatusTone.negative);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.borderStrong),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: accent ?? AppColors.fgMuted),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  label,
                  style: AppText.label,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: AppText.kpiValue,
            overflow: TextOverflow.ellipsis,
          ),
          if (delta != null) ...[
            const SizedBox(height: 6),
            Tag(label: delta!, tone: tone),
          ],
        ],
      ),
    );
  }
}

/// A big thumb-friendly shortcut: icon tile plus two-line label.
class QuickActionTile extends StatelessWidget {
  const QuickActionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.accent,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.45 : 1,
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          side: const BorderSide(color: AppColors.borderStrong),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius:
                        BorderRadius.circular(AppSpacing.radiusMd),
                  ),
                  child: Icon(icon, size: 20, color: accent),
                ),
                const SizedBox(height: 10),
                Text(
                  label,
                  style: AppText.bodyStrong,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One feed line: status dot, title + subtitle, trailing slot.
class FeedRow extends StatelessWidget {
  const FeedRow({
    super.key,
    required this.tone,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final StatusTone tone;
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 5),
          child: StatusDot(tone: tone),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppText.tableCellPrimary),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle!, style: AppText.caption),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          trailing!,
        ],
      ],
    );
  }
}

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
      AppRole.driver => AppColors.driverAccent,
      AppRole.manager => AppColors.managerAccent,
      AppRole.developer => AppColors.developerAccent,
    };

/// The top of a role home: who/where you are, the one number that matters,
/// and the one action you'll take next.
/// The role home banner, built to the design's recipe: a 16px-rounded card
/// filled with the same top-to-bottom gradient the files use
/// (`from-[#1c2229] to-[#14171e]`), an accent-tinted border, a soft black
/// shadow, the label beside a tinted icon chip, and the live pill on the far
/// side of the same row.
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
    this.live = false,
    this.icon,
  });

  final AppRole role;
  final String kicker;
  final String title;
  final String? subtitle;
  final String? value;
  final String? valueLabel;
  final Widget? action;
  final bool live;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final accent = roleAccent(role);
    final identity = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (icon != null) ...[
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.10),
                  border: Border.all(color: accent.withValues(alpha: 0.20)),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
                child: Icon(icon, size: 16, color: accent),
              ),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(
                kicker,
                overflow: TextOverflow.ellipsis,
                style: AppText.label.copyWith(
                  color: AppColors.fgSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (live) ...[
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.10),
                  border: Border.all(color: accent.withValues(alpha: 0.30)),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration:
                          BoxDecoration(color: accent, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                    Text('تحديث لحظي',
                        style: AppText.caption.copyWith(color: accent)),
                  ],
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        Text(title, style: AppText.h1),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(subtitle!, style: AppText.body),
        ],
      ],
    );
    final figure = value == null
        ? null
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The design sets the figure in mono, tightly tracked.
              Text(
                value!,
                style: AppText.mono.copyWith(
                  fontSize: 30,
                  height: 36 / 30,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.03 * 30,
                  color: AppColors.fg,
                ),
              ),
              if (valueLabel != null) ...[
                const SizedBox(height: 2),
                Text(valueLabel!, style: AppText.bodyStrong.copyWith(
                  color: accent,
                )),
              ],
            ],
          );
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        // The files' own gradient stops, not an accent wash: the banner reads
        // as a lit panel rather than a tinted card.
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1C2229), Color(0xFF14171E)],
        ),
        border: Border.all(color: accent.withValues(alpha: 0.30)),
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.55),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, c) {
              // Side by side only when the figure gets real room; otherwise
              // the design's own stacking keeps the numbers from wrapping.
              if (figure != null && c.maxWidth >= 420) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: identity),
                    const SizedBox(width: 12),
                    Flexible(child: figure),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  identity,
                  if (figure != null) ...[
                    const SizedBox(height: 12),
                    figure,
                  ],
                ],
              );
            },
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

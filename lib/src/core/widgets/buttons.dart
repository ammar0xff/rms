import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text.dart';

enum BtnVariant { primary, secondary, ghost, destructive }

class RmsButton extends StatelessWidget {
  const RmsButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.variant = BtnVariant.secondary,
    this.dense = true,
    this.accent,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final BtnVariant variant;
  final bool dense;

  /// Overrides the primary fill. The design says a primary button is filled
  /// with the *role* accent, so a manager's confirm action is emerald rather
  /// than the app-wide cashier amber.
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    // Components → Buttons & Interactive Controls, verbatim:
    //   Primary   "Solid fill using role accent, label in dark ink #0A0A0C
    //              with font-weight 600. Height 40px desktop, 48px touch."
    //   Secondary "Background #16161A, border 1px solid #1E1E22, text #E4E4E7.
    //              On hover/active the border transitions to #27272A with
    //              surface elevation to #1A1A1E."
    final (bg, border, fg) = switch (variant) {
      BtnVariant.primary => (
          accent ?? AppColors.brand,
          Colors.transparent,
          AppColors.onBrand,
        ),
      BtnVariant.secondary => (
          AppColors.surfaceSecondary,
          AppColors.control,
          AppColors.fgSecondary,
        ),
      BtnVariant.ghost => (
          Colors.transparent,
          AppColors.control,
          AppColors.fgMuted,
        ),
      BtnVariant.destructive => (
          AppColors.negativeContainer,
          AppColors.destructive,
          AppColors.negative,
        ),
    };

    return Opacity(
      opacity: onPressed == null ? 0.45 : 1,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          hoverColor: variant == BtnVariant.primary
              ? (accent ?? AppColors.brand).withValues(alpha: 0.88)
              : AppColors.surfaceBright,
          child: Container(
            // 40/48px: the minimum comfortable touch targets. dense is for
            // toolbars and table rows; anything a thumb aims at uses normal.
            height: dense ? 40 : 48,
            padding: EdgeInsets.symmetric(horizontal: dense ? 12 : 14),
            decoration: BoxDecoration(
              border: border == Colors.transparent
                  ? null
                  : Border.all(color: border),
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 16, color: fg),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.body.copyWith(
                      color: fg,
                      // "label in dark ink with font-weight 600"
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class IconBtn extends StatelessWidget {
  const IconBtn({super.key, required this.icon, this.onPressed, this.tooltip});

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final btn = Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        hoverColor: AppColors.hover,
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.control),
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          ),
          child: Icon(icon, size: 18, color: AppColors.fgMuted),
        ),
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip!, child: btn);
  }
}

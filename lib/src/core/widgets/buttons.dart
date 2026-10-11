import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text.dart';

enum BtnVariant { primary, secondary, ghost }

class RmsButton extends StatelessWidget {
  const RmsButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.variant = BtnVariant.secondary,
    this.dense = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final BtnVariant variant;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final (bg, border, fg) = switch (variant) {
      BtnVariant.primary => (AppColors.fg, Colors.transparent, AppColors.base),
      BtnVariant.secondary => (
          Colors.transparent,
          AppColors.control,
          AppColors.fgSecondary,
        ),
      BtnVariant.ghost => (
          Colors.transparent,
          AppColors.control,
          AppColors.fgMuted,
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
              ? Colors.transparent
              : AppColors.hover,
          child: Container(
            height: dense ? 28 : 36,
            padding: EdgeInsets.symmetric(horizontal: dense ? 10 : 14),
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
                  Icon(icon, size: 13, color: fg),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: AppText.caption.copyWith(
                    color: fg,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
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
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.control),
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          ),
          child: Icon(icon, size: 14, color: AppColors.fgMuted),
        ),
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip!, child: btn);
  }
}

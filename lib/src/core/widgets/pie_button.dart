import 'package:flutter/material.dart';
import '../../domain/models/app_role.dart';
import '../theme/pie_colors.dart';
import '../theme/pie_typography.dart';

enum PieButtonVariant {
  primary,
  secondary,
  ghost,
  destructive,
}

/// PIE Action Button
///
/// Hostile environment design:
/// - Guaranteed 44x44 minimum hit target for fast-moving, greasy-handed operators.
/// - High contrast: primary buttons use deep dark ink on bright accent.
/// - Tactile feedback on touch.
class PieButton extends StatelessWidget {
  const PieButton({
    super.key,
    required this.onPressed,
    required this.label,
    this.icon,
    this.variant = PieButtonVariant.primary,
    Color? accentColor,
    AppRole? role,
    this.isFullWidth = false,
    this.isLoading = false,
    this.height = 48,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
  }) : accentColor = accentColor ?? (role != null ? (role == AppRole.cashier ? PieColors.cashierAccent : role == AppRole.driver ? PieColors.driverAccent : role == AppRole.manager ? PieColors.managerAccent : PieColors.systemAccent) : null);

  factory PieButton.primary({
    required VoidCallback? onPressed,
    required String label,
    IconData? icon,
    Color? accentColor,
    bool isFullWidth = false,
    bool isLoading = false,
    double height = 48,
  }) {
    return PieButton(
      onPressed: onPressed,
      label: label,
      icon: icon,
      variant: PieButtonVariant.primary,
      accentColor: accentColor,
      isFullWidth: isFullWidth,
      isLoading: isLoading,
      height: height,
    );
  }

  factory PieButton.secondary({
    required VoidCallback? onPressed,
    required String label,
    IconData? icon,
    bool isFullWidth = false,
    double height = 48,
  }) {
    return PieButton(
      onPressed: onPressed,
      label: label,
      icon: icon,
      variant: PieButtonVariant.secondary,
      isFullWidth: isFullWidth,
      height: height,
    );
  }

  factory PieButton.ghost({
    required VoidCallback? onPressed,
    required String label,
    IconData? icon,
    bool isFullWidth = false,
    double height = 48,
  }) {
    return PieButton(
      onPressed: onPressed,
      label: label,
      icon: icon,
      variant: PieButtonVariant.ghost,
      isFullWidth: isFullWidth,
      height: height,
    );
  }

  factory PieButton.destructive({
    required VoidCallback? onPressed,
    required String label,
    IconData? icon,
    bool isFullWidth = false,
    double height = 48,
  }) {
    return PieButton(
      onPressed: onPressed,
      label: label,
      icon: icon,
      variant: PieButtonVariant.destructive,
      isFullWidth: isFullWidth,
      height: height,
    );
  }

  final VoidCallback? onPressed;
  final String label;
  final IconData? icon;
  final PieButtonVariant variant;
  final Color? accentColor;
  final bool isFullWidth;
  final bool isLoading;
  final double height;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final effectiveAccent = accentColor ?? PieColors.cashierAccent;

    Color bg;
    Color fg;
    Border? border;

    switch (variant) {
      case PieButtonVariant.primary:
        bg = onPressed == null ? effectiveAccent.withOpacity(0.4) : effectiveAccent;
        fg = const Color(0xFF0F1117); // Dark high-contrast ink
        break;
      case PieButtonVariant.secondary:
        bg = PieColors.surface2;
        fg = PieColors.ink;
        border = Border.all(color: PieColors.border, width: 1);
        break;
      case PieButtonVariant.ghost:
        bg = Colors.transparent;
        fg = PieColors.inkSecondary;
        border = Border.all(color: PieColors.border, width: 1);
        break;
      case PieButtonVariant.destructive:
        bg = PieColors.stateError;
        fg = Colors.white;
        break;
    }

    final buttonContent = Row(
      mainAxisSize: isFullWidth ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (isLoading) ...[
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(fg),
            ),
          ),
          const SizedBox(width: 8),
        ] else if (icon != null) ...[
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(
            label,
            style: PieTypography.bodyStrong.copyWith(
              color: fg,
              fontSize: height < 44 ? 13 : 14,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );

    return ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: 44,
        minHeight: 44, // 44x44 hit target rule
        maxWidth: isFullWidth ? double.infinity : 400,
      ),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: isLoading ? null : onPressed,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: height,
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: border,
            ),
            child: buttonContent,
          ),
        ),
      ),
    );
  }
}

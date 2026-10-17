import 'package:flutter/material.dart';
import '../../domain/models/app_role.dart';
import '../theme/pie_colors.dart';

/// PIE Card Primitive
///
/// Implements the tonal ladder for visual depth:
/// - Tone-based hierarchy (surface1, surface2, well)
/// - Fine hairline border (1px)
/// - Optional active state with directional accent glow / bloom
class PieCard extends StatelessWidget {
  const PieCard({
    super.key,
    required this.child,
    Color? surfaceColor,
    Color? surface,
    this.borderColor,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.borderRadius = 12,
    this.onTap,
    this.isActive = false,
    Color? activeColor,
    AppRole? role,
    this.width,
    this.height,
  })  : surfaceColor = surface ?? surfaceColor,
        activeColor = activeColor ?? (role != null ? (role == AppRole.cashier ? PieColors.cashierAccent : role == AppRole.driver ? PieColors.driverAccent : role == AppRole.manager ? PieColors.managerAccent : PieColors.systemAccent) : null);

  final Widget child;
  final Color? surfaceColor;
  final Color? borderColor;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final VoidCallback? onTap;
  final bool isActive;
  final Color? activeColor;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final effectiveSurface = surfaceColor ?? PieColors.surface1;
    final effectiveActiveColor = activeColor ?? PieColors.cashierAccent;

    final effectiveBorder = isActive
        ? Border.all(color: effectiveActiveColor, width: 1.5)
        : Border.all(color: borderColor ?? PieColors.border, width: 1);

    final boxDecoration = BoxDecoration(
      color: effectiveSurface,
      borderRadius: BorderRadius.circular(borderRadius),
      border: effectiveBorder,
      boxShadow: isActive
          ? [
              BoxShadow(
                color: effectiveActiveColor.withOpacity(0.18),
                blurRadius: 12,
                spreadRadius: 1,
              ),
            ]
          : null,
    );

    Widget content = Container(
      width: width,
      height: height,
      margin: margin,
      decoration: boxDecoration,
      padding: padding,
      child: child,
    );

    if (onTap != null) {
      content = Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(borderRadius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(borderRadius),
          splashColor: (activeColor ?? PieColors.ink).withOpacity(0.08),
          highlightColor: (activeColor ?? PieColors.ink).withOpacity(0.04),
          child: content,
        ),
      );
    }

    return content;
  }
}

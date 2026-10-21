import 'package:flutter/material.dart';
import '../../domain/models/app_role.dart';
import '../theme/pie_colors.dart';
import '../theme/pie_radius.dart';

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
    this.borderRadius = PieRadius.lg,
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

    final effectiveBorderSide = isActive
        ? BorderSide(color: effectiveActiveColor, width: 1.5)
        : BorderSide(color: borderColor ?? PieColors.border, width: 1);

    Widget content;
    if (onTap != null) {
      content = Material(
        color: effectiveSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadius),
          side: effectiveBorderSide,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(borderRadius),
          splashColor: (activeColor ?? PieColors.ink).withOpacity(0.08),
          highlightColor: (activeColor ?? PieColors.ink).withOpacity(0.04),
          child: Container(
            width: width,
            height: height,
            padding: padding,
            child: child,
          ),
        ),
      );
    } else {
      content = Material(
        color: effectiveSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadius),
          side: effectiveBorderSide,
        ),
        clipBehavior: Clip.antiAlias,
        child: Container(
          width: width,
          height: height,
          padding: padding,
          child: child,
        ),
      );
    }

    if (margin != null) {
      content = Padding(padding: margin!, child: content);
    }

    return content;
  }
}

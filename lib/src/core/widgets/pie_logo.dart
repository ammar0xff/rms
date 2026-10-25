import 'package:flutter/material.dart';
import '../theme/pie_colors.dart';

/// Reusable PIE Brand Logo Widget.
///
/// Features:
/// - Distinctive near-black squircle container with amber glowing perimeter.
/// - Crisp high-contrast Greek letter `π` in warm golden amber.
/// - Configurable [size], optional [showGlow], custom [borderRadius], or image asset fallback.
class PieLogo extends StatelessWidget {
  const PieLogo({
    super.key,
    this.size = 48,
    this.showGlow = true,
    this.borderRadius,
    this.useAsset = false,
  });

  /// The width and height of the square logo in logical pixels.
  final double size;

  /// Whether to render the ambient golden glow behind the logo.
  final bool showGlow;

  /// Custom corner radius. If null, defaults to 26% of [size].
  final BorderRadius? borderRadius;

  /// Whether to render the compiled raster asset [assets/icons/app_icon.png].
  final bool useAsset;

  @override
  Widget build(BuildContext context) {
    final effectiveRadius = borderRadius ?? BorderRadius.circular(size * 0.26);

    if (useAsset) {
      return Semantics(
        label: 'شعار باى للعمليات (PIE)',
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: effectiveRadius,
            boxShadow: showGlow
                ? [
                    BoxShadow(
                      color: PieColors.roleCashier.withValues(alpha: 0.35),
                      blurRadius: size * 0.35,
                      spreadRadius: size * 0.04,
                    ),
                  ]
                : null,
          ),
          child: ClipRRect(
            borderRadius: effectiveRadius,
            child: Image.asset(
              'assets/icons/app_icon.png',
              width: size,
              height: size,
              fit: BoxFit.cover,
            ),
          ),
        ),
      );
    }

    final borderWidth = (size * 0.025).clamp(1.2, 3.5);
    final fontSize = size * 0.56;

    return Semantics(
      label: 'شعار باى للعمليات (PIE)',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: PieColors.surface2,
          borderRadius: effectiveRadius,
          border: Border.all(
            color: PieColors.roleCashier,
            width: borderWidth,
          ),
          boxShadow: showGlow
              ? [
                  BoxShadow(
                    color: PieColors.roleCashier.withValues(alpha: 0.32),
                    blurRadius: size * 0.36,
                    spreadRadius: size * 0.03,
                  ),
                ]
              : null,
        ),
        child: Center(
          child: Text(
            'π',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: PieColors.roleCashier,
              fontSize: fontSize,
              fontWeight: FontWeight.w900,
              height: 1.05,
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

enum SurfaceLevel { content, secondary, sunken }

class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding,
    this.level = SurfaceLevel.content,
    this.clip = false,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final SurfaceLevel level;
  final bool clip;

  @override
  Widget build(BuildContext context) {
    final (bg, border) = switch (level) {
      SurfaceLevel.content => (AppColors.surface, AppColors.borderStrong),
      SurfaceLevel.secondary => (
          AppColors.surfaceSecondary,
          AppColors.borderSubtle,
        ),
      SurfaceLevel.sunken => (AppColors.surfaceSunken, AppColors.borderFaint),
    };

    final radius = BorderRadius.circular(AppSpacing.radiusLg);
    return Container(
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border),
        borderRadius: radius,
      ),
      clipBehavior: clip ? Clip.antiAlias : Clip.none,
      padding: padding ?? const EdgeInsets.all(AppSpacing.lg),
      child: child,
    );
  }
}

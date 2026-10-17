import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_spacing.dart';
import 'app_text.dart';

/// The design is dark-only and shadow-free — "Blur filters and diffused drop
/// shadows are omitted to maintain 60 FPS rendering performance on low-spec
/// hardware" — so depth here is entirely tonal, and no elevation shadow or
/// surface tint is ever introduced.
abstract final class AppTheme {
  static ThemeData light() => dark();

  static ThemeData dark() {
    const scheme = ColorScheme.dark(
      primary: AppColors.brand,
      onPrimary: AppColors.onBrand,
      surface: AppColors.base,
      onSurface: AppColors.fgSecondary,
      surfaceContainerHighest: AppColors.surfaceBright,
      onSurfaceVariant: AppColors.fgMuted,
      outline: AppColors.outline,
      outlineVariant: AppColors.outlineVariant,
      error: AppColors.negative,
      onError: AppColors.negative,
      secondary: AppColors.secondary,
      tertiary: AppColors.tertiary,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.base,
      canvasColor: AppColors.base,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      dividerColor: AppColors.borderSubtle,
      dividerTheme: const DividerThemeData(
        color: AppColors.borderSubtle,
        thickness: 1,
        space: 1,
      ),
      textTheme: const TextTheme(
        bodyMedium: AppText.body,
        bodySmall: AppText.caption,
        titleMedium: AppText.bodyStrong,
        titleLarge: AppText.h1,
        labelSmall: AppText.label,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.base,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        toolbarHeight: AppSpacing.topBarHeight,
        titleTextStyle: AppText.pageTitle,
        iconTheme: IconThemeData(color: AppColors.fgMuted, size: 18),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.base,
        indicatorColor: Colors.transparent,
        elevation: 0,
        height: AppSpacing.topBarHeight,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppText.label.copyWith(color: AppColors.brand)
              : AppText.label.copyWith(color: AppColors.fgDim),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 20,
            color: states.contains(WidgetState.selected)
                ? AppColors.brand
                : AppColors.fgDim,
          ),
        ),
      ),
      iconTheme: const IconThemeData(color: AppColors.fgMuted, size: 18),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(AppColors.outlineVariant),
        radius: const Radius.circular(4),
        thickness: WidgetStateProperty.all(4),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.inverseSurface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        ),
        textStyle: AppText.caption.copyWith(color: AppColors.inverseOnSurface),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_spacing.dart';
import 'app_text.dart';

/// The design ships a dark-only system, so there is no light variant to fall
/// back to: [dark] is the theme, and [light] is an alias kept so callers that
/// name the brightness keep working.
abstract final class AppTheme {
  static ThemeData light() => dark();

  static ThemeData dark() {
    const scheme = ColorScheme.dark(
      primary: AppColors.brand,
      onPrimary: AppColors.onBrand,
      primaryContainer: AppColors.brandContainer,
      onPrimaryContainer: AppColors.onBrandContainer,
      secondary: AppColors.secondary,
      onSecondary: AppColors.onSecondary,
      secondaryContainer: AppColors.secondaryContainer,
      onSecondaryContainer: AppColors.onSecondaryContainer,
      tertiary: AppColors.tertiary,
      onTertiary: AppColors.onTertiary,
      tertiaryContainer: AppColors.tertiaryContainer,
      onTertiaryContainer: AppColors.onTertiaryContainer,
      surface: AppColors.surface,
      onSurface: AppColors.fg,
      surfaceContainerHighest: AppColors.surfaceHighest,
      onSurfaceVariant: AppColors.fgSecondary,
      outline: AppColors.outline,
      outlineVariant: AppColors.outlineVariant,
      error: AppColors.negative,
      onError: AppColors.onNegative,
      errorContainer: AppColors.negativeContainer,
      onErrorContainer: AppColors.onNegativeContainer,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.base,
      canvasColor: AppColors.base,
      // The design animates its own state (active:scale-95) rather than
      // flashing a system ripple, so the splash is suppressed to match.
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
        centerTitle: false,
        toolbarHeight: AppSpacing.topBarHeight,
        titleTextStyle: AppText.pageTitle,
        iconTheme: IconThemeData(color: AppColors.fgMuted, size: 18),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surfaceLow,
        indicatorColor: Colors.transparent,
        elevation: 0,
        height: 64,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppText.label.copyWith(color: AppColors.brandContainer)
              : AppText.label.copyWith(color: AppColors.fgMuted),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 20,
            color: states.contains(WidgetState.selected)
                ? AppColors.brandContainer
                : AppColors.fgMuted,
          ),
        ),
      ),
      iconTheme: const IconThemeData(color: AppColors.fgMuted, size: 18),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(AppColors.fgGhost),
        radius: const Radius.circular(8),
        thickness: WidgetStateProperty.all(6),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.inverseSurface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          border: Border.all(color: AppColors.outlineVariant),
        ),
        textStyle: AppText.caption.copyWith(color: AppColors.inverseOnSurface),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_spacing.dart';
import 'app_text.dart';

abstract final class AppTheme {
  static ThemeData light() {
    const scheme = ColorScheme.light(
      primary: AppColors.brand,
      onPrimary: Color(0xFFFFFBF2),
      secondary: AppColors.info,
      surface: AppColors.surface,
      onSurface: AppColors.fg,
      error: AppColors.negative,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
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
        labelSmall: AppText.label,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.base,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        toolbarHeight: AppSpacing.topBarHeight,
        titleTextStyle: AppText.pageTitle,
        iconTheme: IconThemeData(color: AppColors.fgMuted, size: 16),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surfaceSecondary,
        indicatorColor: Colors.transparent,
        elevation: 0,
        height: 60,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppText.label.copyWith(color: AppColors.fg)
              : AppText.label,
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 18,
            color: states.contains(WidgetState.selected)
                ? AppColors.fg
                : AppColors.fgDim,
          ),
        ),
      ),
      iconTheme: const IconThemeData(color: AppColors.fgMuted, size: 16),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(AppColors.fgGhost),
        radius: const Radius.circular(8),
        thickness: WidgetStateProperty.all(6),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: const Color(0xFF1F1F23),
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          border: Border.all(color: AppColors.control),
        ),
        textStyle: AppText.caption.copyWith(color: AppColors.fg),
      ),
    );
  }
}
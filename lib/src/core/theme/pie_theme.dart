import 'package:flutter/material.dart';
import '../../domain/models/app_role.dart';
import 'pie_colors.dart';
import 'pie_typography.dart';

/// PIE Theme Definition
///
/// Dark-only, RTL-native, engineered for glare resistance and glanceable state.
abstract final class PieTheme {
  static ThemeData themeFor(AppRole role) {
    final roleAccent = PieColors.accentFor(role);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: PieColors.canvas,
      canvasColor: PieColors.canvas,
      cardColor: PieColors.surface1,
      dividerColor: PieColors.border,
      primaryColor: roleAccent,
      fontFamily: PieTypography.fontFamilyArabic,
      colorScheme: ColorScheme.dark(
        primary: roleAccent,
        onPrimary: Colors.black,
        secondary: roleAccent,
        onSecondary: Colors.black,
        surface: PieColors.surface1,
        onSurface: PieColors.ink,
        error: PieColors.stateError,
        onError: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: PieColors.canvas,
        foregroundColor: PieColors.ink,
        elevation: 0,
        centerTitle: false,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: PieColors.surface1,
        selectedItemColor: roleAccent,
        unselectedItemColor: PieColors.inkMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: PieColors.surfaceOverlay,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: PieColors.border, width: 1),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: PieColors.surfaceOverlay,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          side: BorderSide(color: PieColors.border, width: 1),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: PieColors.well,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: PieColors.border, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: PieColors.border, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: roleAccent, width: 1.5),
        ),
        hintStyle: PieTypography.body.copyWith(color: PieColors.inkMuted),
        labelStyle: PieTypography.label.copyWith(color: PieColors.inkSecondary),
      ),
    );
  }
}

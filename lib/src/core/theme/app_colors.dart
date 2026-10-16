import 'package:flutter/material.dart';

abstract final class AppColors {
  static const base = Color(0xFFF7F7F8);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceSecondary = Color(0xFFFBFBFC);
  static const surfaceSunken = Color(0xFFF1F1F3);
  static const hover = Color(0xFFEDEDEF);

  static const borderStrong = Color(0xFFE3E3E7);
  static const borderSubtle = Color(0xFFEBEBEE);
  static const borderFaint = Color(0xFFF1F1F3);
  static const control = Color(0xFFD7D7DC);

  static const fg = Color(0xFF09090B);
  static const fgBright = Color(0xFF26262A);
  static const fgSecondary = Color(0xFF52525B);
  static const fgMuted = Color(0xFF71717A);
  static const fgDim = Color(0xFF9A9AA4);
  static const fgGhost = Color(0xFFB9B9C1);

  static const brand = Color(0xFFB45309);
  static const brandSoft = Color(0x1AB45309);
  static const brandLine = Color(0x3DB45309);

  static const positive = Color(0xFF059669);
  static const negative = Color(0xFFDC2626);
  static const warning = Color(0xFFD97706);
  static const info = Color(0xFF2563EB);
  static const purple = Color(0xFF7C3AED);

  /// Role accents — one family, five uniforms. Each role home tints its hero
  /// and key actions with its accent; everything else stays on the shared
  /// warm-neutral palette so any operator can cover any screen.
  static const cashierAccent = brand;
  static const driverAccent = Color(0xFF0284C7);
  static const managerAccent = Color(0xFF059669);
  static const developerAccent = purple;
}
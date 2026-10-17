import 'package:flutter/material.dart';

/// The Stitch "Industrial Tactile POS" dark design system.
///
/// Every value here is copied verbatim out of the design files' own
/// `tailwind.config` blocks — no lightening, no warming, no "close enough".
/// The 19 dominant screens ship a byte-identical 47-token config, which is
/// what this file reproduces; the named aliases below come from the screens
/// that use the alternate `base/card/border` spelling of the same palette.
///
/// The one addition is [roleAccentFor]: the design carries one amber/emerald
/// family and says nothing about per-role colour, so role identity maps onto
/// the tokens the design already defines (primary / secondary / tertiary)
/// instead of inventing a fifth hue.
abstract final class AppColors {
  // --- Surfaces: the elevation ladder, verbatim ---
  static const surfaceLowest = Color(0xFF0E0E10);
  static const surfaceLow = Color(0xFF1B1B1D);
  static const surfaceCard = Color(0xFF201F21);
  static const surfaceHigh = Color(0xFF2A2A2C);
  static const surfaceHighest = Color(0xFF353437);
  static const surfaceVariant = Color(0xFF353437);

  /// The screens call the page background `background`, `surface` and `base`
  /// interchangeably; all three resolve to the same `#131315`.
  static const base = Color(0xFF131315);
  static const surface = Color(0xFF131315);
  static const surfaceSecondary = Color(0xFF1B1B1D);
  static const surfaceSunken = Color(0xFF0E0E10);
  static const surfaceBright = Color(0xFF39393B);
  static const hover = Color(0xFF2A2A2C);

  // --- Borders / outlines ---
  static const borderStrong = Color(0xFF353437);
  static const borderSubtle = Color(0xFF2A2A2C);
  static const borderFaint = Color(0xFF201F21);
  static const control = Color(0xFF2A2A2C);
  static const outline = Color(0xFF9F8E7A);
  static const outlineVariant = Color(0xFF524434);

  // --- Foreground ---
  static const fg = Color(0xFFE5E1E4);
  static const fgBright = Color(0xFFFFFFFF);
  static const fgSecondary = Color(0xFFD7C3AE);
  static const fgMuted = Color(0xFF9F8E7A);
  static const fgDim = Color(0xFF9F8E7A);
  static const fgGhost = Color(0xFF6C6558);

  // --- Brand: the amber family (primary) ---
  static const brand = Color(0xFFFFC77F);
  static const brandContainer = Color(0xFFF5A524);
  static const brandFixed = Color(0xFFFFDDB5);
  static const brandFixedDim = Color(0xFFFFB957);
  static const brandHover = Color(0xFFFFB944);
  static const onBrand = Color(0xFF462B00);
  static const onBrandContainer = Color(0xFF643F00);
  static const onBrandFixed = Color(0xFF2A1800);
  static const onBrandFixedVariant = Color(0xFF643F00);

  static const brandSoft = Color(0x33F5A524);
  static const brandLine = Color(0x4DF5A524);

  // --- Secondary: the mint family (success / delivery) ---
  static const secondary = Color(0xFF45DFA4);
  static const secondaryContainer = Color(0xFF00BD85);
  static const secondaryFixed = Color(0xFF68FCBF);
  static const secondaryFixedDim = Color(0xFF45DFA4);
  static const onSecondary = Color(0xFF003825);
  static const onSecondaryContainer = Color(0xFF00452E);
  static const onSecondaryFixed = Color(0xFF002114);
  static const onSecondaryFixedVariant = Color(0xFF005137);

  static const positive = Color(0xFF45DFA4);
  static const secondarySoft = Color(0x2645DFA4);

  // --- Tertiary: the periwinkle family (info / driver) ---
  static const tertiary = Color(0xFFB6D3FF);
  static const tertiaryContainer = Color(0xFF84B8FF);
  static const tertiaryFixed = Color(0xFFD4E3FF);
  static const tertiaryFixedDim = Color(0xFFA4C9FF);
  static const onTertiary = Color(0xFF00315D);
  static const onTertiaryContainer = Color(0xFF004883);

  static const info = Color(0xFF84B8FF);
  static const tertiarySoft = Color(0x2684B8FF);

  // --- Error ---
  static const negative = Color(0xFFFFB4AB);
  static const negativeContainer = Color(0xFF93000A);
  static const onNegative = Color(0xFF690005);
  static const onNegativeContainer = Color(0xFFFFDAD6);
  static const negativeSoft = Color(0x26FFB4AB);

  // --- Warning ---
  static const warning = Color(0xFFF59E0B);

  static const purple = Color(0xFFB6D3FF);

  // --- Inverse (used by tooltips and the scrim-side chips) ---
  static const inverseSurface = Color(0xFFE5E1E4);
  static const inverseOnSurface = Color(0xFF303032);
  static const inversePrimary = Color(0xFF835400);

  /// Role accents, drawn only from the design's own families.
  ///
  /// Cashier sits on the amber the POS screens use, driver on the periwinkle
  /// the delivery screens use, manager on the mint the ops screens use, and
  /// developer on the tertiary-fixed tint the sysadmin screens use.
  static const cashierAccent = brand;
  static const driverAccent = tertiary;
  static const managerAccent = secondary;
  static const developerAccent = tertiaryFixedDim;

  /// The design has no dedicated warning hue, so it borrows the amber
  /// family's dimmed step.
  static const warningSoft = Color(0x26FFB957);
}

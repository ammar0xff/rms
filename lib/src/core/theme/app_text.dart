import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Type scale transcribed from the design files' own `fontSize` blocks.
///
/// The designs name thirteen roles. Flutter's style names are kept because the
/// app already uses them everywhere, and each maps to the closest design role:
///   numeric-display -> hero, numeric-lg -> kpiValue,
///   headline-lg/md/sm -> h1/h2/pageTitle,
///   body-lg/md/sm -> bodyStrong/body/tableCell,
///   label-lg/md/sm -> label/caption/tableHeader.
///
/// Numerals carry tabular figures so money columns do not jitter; the design's
/// mono face does the same job for figures it sets in `numeric-*`.
abstract final class AppText {
  /// Tabular figures — the design's numeric roles all use fixed-width digits.
  static const List<FontFeature> _num = [
    FontFeature.tabularFigures(),
  ];

  static const _sans = 'IBMPlexSansArabic';
  static const _mono = 'JetBrainsMono';

  /// design `numeric-display`: 36px / 44px, weight 600, -0.03em
  static const hero = TextStyle(
    fontFamily: _sans,
    fontSize: 36,
    height: 44 / 36,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.03 * 36,
    color: AppColors.fg,
    fontFeatures: _num,
  );

  /// design `headline-lg`: 24px / 32px, weight 600
  static const h1 = TextStyle(
    fontFamily: _sans,
    fontSize: 24,
    height: 32 / 24,
    fontWeight: FontWeight.w600,
    color: AppColors.fg,
    fontFeatures: _num,
  );

  /// design `headline-sm`: 16px / 24px, weight 600
  static const h2 = TextStyle(
    fontFamily: _sans,
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeight.w600,
    color: AppColors.fg,
    fontFeatures: _num,
  );

  /// design `headline-md`: 20px / 28px, weight 600
  static const pageTitle = TextStyle(
    fontFamily: _sans,
    fontSize: 20,
    height: 28 / 20,
    fontWeight: FontWeight.w600,
    color: AppColors.fg,
    fontFeatures: _num,
  );

  /// design `body-lg`: 15px / 22px, weight 400
  static const sectionHeading = TextStyle(
    fontFamily: _sans,
    fontSize: 15,
    height: 22 / 15,
    fontWeight: FontWeight.w400,
    color: AppColors.fgSecondary,
    fontFeatures: _num,
  );

  /// design `body-md`: 13px / 18px, weight 400
  static const body = TextStyle(
    fontFamily: _sans,
    fontSize: 13,
    height: 18 / 13,
    fontWeight: FontWeight.w400,
    color: AppColors.fgSecondary,
    fontFeatures: _num,
  );

  /// design `body-lg` at weight 500
  static const bodyStrong = TextStyle(
    fontFamily: _sans,
    fontSize: 15,
    height: 22 / 15,
    fontWeight: FontWeight.w500,
    color: AppColors.fg,
    fontFeatures: _num,
  );

  /// design `body-md` at the muted step
  static const tableCell = TextStyle(
    fontFamily: _sans,
    fontSize: 13,
    height: 18 / 13,
    color: AppColors.fgMuted,
    fontFeatures: _num,
  );

  /// design `body-md` at weight 500 on the bright step
  static const tableCellPrimary = TextStyle(
    fontFamily: _sans,
    fontSize: 13,
    height: 18 / 13,
    fontWeight: FontWeight.w500,
    color: AppColors.fg,
    fontFeatures: _num,
  );

  /// design `label-sm`: 11px / 14px, +0.02em, weight 500
  static const tableHeader = TextStyle(
    fontFamily: _sans,
    fontSize: 11,
    height: 14 / 11,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.02 * 11,
    color: AppColors.fgMuted,
    fontFeatures: _num,
  );

  /// design `label-md`: 12px / 16px, weight 500
  static const label = TextStyle(
    fontFamily: _sans,
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w500,
    color: AppColors.fgSecondary,
    fontFeatures: _num,
  );

  /// design `label-sm` at the dim step
  static const caption = TextStyle(
    fontFamily: _sans,
    fontSize: 11,
    height: 14 / 11,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.02 * 11,
    color: AppColors.fgDim,
    fontFeatures: _num,
  );

  /// design `numeric-lg`: 20px / 26px, -0.02em, weight 600
  static const kpiValue = TextStyle(
    fontFamily: _sans,
    fontSize: 20,
    height: 26 / 20,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.02 * 20,
    color: AppColors.fg,
    fontFeatures: _num,
  );

  static const navItem = TextStyle(
    fontFamily: _sans,
    fontSize: 15,
    height: 22 / 15,
    fontWeight: FontWeight.w500,
    color: AppColors.fgSecondary,
    fontFeatures: _num,
  );

  /// design `numeric-md` in the mono face
  static const mono = TextStyle(
    fontFamily: _mono,
    fontSize: 14,
    height: 18 / 14,
    letterSpacing: -0.01 * 14,
    color: AppColors.fgMuted,
    fontFeatures: _num,
  );

  /// design `label-sm` on the mono face — node IDs, hashes, queue numbers.
  static const monoSmall = TextStyle(
    fontFamily: _mono,
    fontSize: 11,
    height: 14 / 11,
    letterSpacing: 0.02 * 11,
    fontWeight: FontWeight.w500,
    color: AppColors.fgMuted,
    fontFeatures: _num,
  );
}

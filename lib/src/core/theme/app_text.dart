import 'package:flutter/material.dart';

import 'app_colors.dart';

abstract final class AppText {
  static const List<FontFeature> _tnum = [FontFeature.tabularFigures()];

  static const hero = TextStyle(
    fontSize: 44,
    fontWeight: FontWeight.w600,
    letterSpacing: -1.6,
    height: 1.0,
    color: AppColors.fg,
    fontFeatures: _tnum,
  );

  static const h1 = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.4,
    color: AppColors.fg,
  );

  static const h2 = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
    color: AppColors.fg,
  );

  static const pageTitle = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.1,
    color: AppColors.fgBright,
  );

  static const sectionHeading = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: AppColors.fgSecondary,
  );

  static const body = TextStyle(
    fontSize: 12.5,
    fontWeight: FontWeight.w400,
    height: 1.45,
    color: AppColors.fgSecondary,
  );

  static const bodyStrong = TextStyle(
    fontSize: 12.5,
    fontWeight: FontWeight.w500,
    color: AppColors.fgBright,
  );

  static const tableCell = TextStyle(
    fontSize: 11.5,
    color: AppColors.fgMuted,
  );

  static const tableCellPrimary = TextStyle(
    fontSize: 11.5,
    fontWeight: FontWeight.w500,
    color: AppColors.fgBright,
  );

  static const tableHeader = TextStyle(
    fontSize: 9.5,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.8,
    color: AppColors.fgDim,
  );

  static const label = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.5,
    color: AppColors.fgMuted,
  );

  static const caption = TextStyle(
    fontSize: 10.5,
    color: AppColors.fgDim,
    fontFeatures: _tnum,
  );

  static const kpiValue = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.4,
    color: AppColors.fgBright,
    fontFeatures: _tnum,
  );

  static const navItem = TextStyle(
    fontSize: 12.5,
    fontWeight: FontWeight.w500,
  );

  static const mono = TextStyle(
    fontFamily: 'monospace',
    fontSize: 11,
    color: AppColors.fgMuted,
  );
}

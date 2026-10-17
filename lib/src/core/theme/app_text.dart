import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Type scale transcribed from the project's `designMd` typography block.
///
/// The design splits the faces by job, not by size:
///
///   IBM Plex Sans   → headline-xl/lg/md/sm, body-lg/md/sm
///   JetBrains Mono  → label-lg/md/sm, numeric-display/lg/md
///
///   "Dedicated exclusively to currency outputs, order tracking codes, SKUs,
///    inventory counts, and elapsed prep timers."
///
/// So the *labels* are monospace here, not just the numerals. The Flutter
/// style names are kept because the app already uses them; each maps to the
/// design role it stands in for.
///
/// Two rules from the design are implemented rather than described:
///   • "Line heights for Arabic content must incorporate a 4px vertical
///     expansion over default Latin baselines." Every style adds 4px of
///     leading over its nominal size.
///   • "Monospace numbers remain strictly left-to-right within RTL layouts."
///     [TextStyle] has no direction parameter, so this is applied where it
///     matters — see `LtrIsolate` in widgets/blocks.dart, which wraps a
///     numeral in a left-to-right [Directionality] so a negative delta or an
///     MM:SS timer cannot reorder inside an Arabic line.
abstract final class AppText {
  /// Tabular figures — every `numeric-*` role is fixed-width.
  static const List<FontFeature> _num = [FontFeature.tabularFigures()];

  static const _sans = 'IBMPlexSansArabic';
  static const _mono = 'JetBrainsMono';

  /// The design's stated 4px vertical expansion for Arabic leading.
  static double _arabicHeight(double size, double lineHeight) =>
      (lineHeight + 4) / size;

  // --- numeric-* → JetBrains Mono -----------------------------------------

  /// numeric-display: 36px / 44px, 600, -0.03em
  static const hero = TextStyle(
    fontFamily: _mono,
    fontSize: 36,
    height: 1.333,
    fontWeight: FontWeight.w600,
    letterSpacing: -1.08,
    color: AppColors.fg,
    fontFeatures: _num,
  );

  /// numeric-lg: 20px / 26px, 600, -0.02em
  static const kpiValue = TextStyle(
    fontFamily: _mono,
    fontSize: 20,
    height: 1.5,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.4,
    color: AppColors.fg,
    fontFeatures: _num,
  );

  /// numeric-md: 14px / 18px, 500, -0.01em
  static const mono = TextStyle(
    fontFamily: _mono,
    fontSize: 14,
    height: 1.5,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.14,
    color: AppColors.fgMuted,
    fontFeatures: _num,
  );

  /// label-sm in mono — order codes, node IDs, status dot captions.
  static const monoSmall = TextStyle(
    fontFamily: _mono,
    fontSize: 11,
    height: 1.5,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.22,
    color: AppColors.fgDim,
    fontFeatures: _num,
  );

  // --- label-* → JetBrains Mono -------------------------------------------

  /// label-md: 12px / 16px, 500 — the design's badge and chip label.
  static const label = TextStyle(
    fontFamily: _mono,
    fontSize: 12,
    height: 1.5,
    fontWeight: FontWeight.w500,
    color: AppColors.fgMuted,
    fontFeatures: _num,
  );

  // --- headline-* / body-* → IBM Plex Sans --------------------------------

  /// headline-lg: 24px / 32px, 600
  static const h1 = TextStyle(
    fontFamily: _sans,
    fontSize: 24,
    height: 1.5,
    fontWeight: FontWeight.w600,
    color: AppColors.fg,
    fontFeatures: _num,
  );

  /// headline-sm: 16px / 24px, 600
  static const h2 = TextStyle(
    fontFamily: _sans,
    fontSize: 16,
    height: 1.5,
    fontWeight: FontWeight.w600,
    color: AppColors.fg,
    fontFeatures: _num,
  );

  /// headline-md: 20px / 28px, 600 — the header's branch line.
  static const pageTitle = TextStyle(
    fontFamily: _sans,
    fontSize: 20,
    height: 1.5,
    fontWeight: FontWeight.w600,
    color: AppColors.fg,
    fontFeatures: _num,
  );

  /// body-lg at weight 500 — table cell primaries.
  static const bodyStrong = TextStyle(
    fontFamily: _sans,
    fontSize: 15,
    height: 1.6,
    fontWeight: FontWeight.w500,
    color: AppColors.fgSecondary,
    fontFeatures: _num,
  );

  /// body-lg: 15px / 22px, 400
  static const sectionHeading = TextStyle(
    fontFamily: _sans,
    fontSize: 15,
    height: 1.6,
    fontWeight: FontWeight.w400,
    color: AppColors.fgSecondary,
    fontFeatures: _num,
  );

  /// body-md: 13px / 18px, 400
  static const body = TextStyle(
    fontFamily: _sans,
    fontSize: 13,
    height: 1.6,
    fontWeight: FontWeight.w400,
    color: AppColors.fgSecondary,
    fontFeatures: _num,
  );

  /// body-md at the primary-body ink, weight 500 — the design's line item.
  static const tableCellPrimary = TextStyle(
    fontFamily: _sans,
    fontSize: 13,
    height: 1.6,
    fontWeight: FontWeight.w500,
    color: AppColors.fgSecondary,
    fontFeatures: _num,
  );

  /// body-md at the muted step — quantities and secondary metadata.
  static const tableCell = TextStyle(
    fontFamily: _sans,
    fontSize: 13,
    height: 1.6,
    fontWeight: FontWeight.w400,
    color: AppColors.fgMuted,
    fontFeatures: _num,
  );

  /// body-sm: 12px / 16px, 400 — the design's micro-copy step.
  static const caption = TextStyle(
    fontFamily: _sans,
    fontSize: 12,
    height: 1.5,
    fontWeight: FontWeight.w400,
    color: AppColors.fgDim,
    fontFeatures: _num,
  );

  /// Data Tables → "Header: uppercase, font size 11px monospace, #71717A"
  static const tableHeader = TextStyle(
    fontFamily: _mono,
    fontSize: 11,
    height: 1.5,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.22,
    color: AppColors.fgDim,
    fontFeatures: _num,
  );

  static const navItem = TextStyle(
    fontFamily: _sans,
    fontSize: 15,
    height: 1.6,
    fontWeight: FontWeight.w500,
    color: AppColors.fgSecondary,
    fontFeatures: _num,
  );

  /// Arabic-leading helper, for the rare style declared inline.
  static double arabicLeading(double size, double nominal) =>
      _arabicHeight(size, nominal);
}

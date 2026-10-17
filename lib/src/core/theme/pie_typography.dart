import 'dart:ui';
import 'package:flutter/material.dart';
import 'pie_colors.dart';

/// PIE Arabic & Monospace Typography System
///
/// Design Rationale & Decisions:
/// - Arabic typography: `IBMPlexSansArabic` with generous leading (1.7–1.8) to give
///   room for diacritics, ascenders, and descenders.
/// - Numerals: `JetBrainsMono` with [FontFeature.tabularFigures()] so prices,
///   quantities, order codes, timers and SKU numbers never jitter or shift.
/// - Numeral system: Western Arabic numerals (`0 1 2 3 4 5 6 7 8 9`) are the deliberate
///   standard across Egyptian commerce, POS hardware, and till receipts.
/// - LTR numeral isolation: Numerals are explicitly rendered in LTR contexts inside RTL
///   flows using directional isolates to prevent `MM:SS`, negative deltas, or currency amounts
///   from rearranging.
abstract final class PieTypography {
  static const String fontFamilyArabic = 'IBMPlexSansArabic';
  static const String fontFamilyMono = 'JetBrainsMono';

  // --- Typographic Scale ---
  static const TextStyle h1 = display;
  static const TextStyle h2 = heading;
  static const TextStyle h3 = subheading;

  /// Display hero (28px / SemiBold / height 1.4)
  static const TextStyle display = TextStyle(
    fontFamily: fontFamilyArabic,
    fontSize: 28,
    fontWeight: FontWeight.w700,
    height: 1.4,
    color: PieColors.ink,
  );

  /// Major Section Heading (20px / SemiBold / height 1.5)
  static const TextStyle heading = TextStyle(
    fontFamily: fontFamilyArabic,
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.5,
    color: PieColors.ink,
  );

  /// Subheading & Card Title (16px / Medium / height 1.6)
  static const TextStyle subheading = TextStyle(
    fontFamily: fontFamilyArabic,
    fontSize: 16,
    fontWeight: FontWeight.w500,
    height: 1.6,
    color: PieColors.ink,
  );

  /// Body Copy (14px / Regular / height 1.75 generous leading)
  static const TextStyle body = TextStyle(
    fontFamily: fontFamilyArabic,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.75,
    color: PieColors.inkSecondary,
  );

  /// Strong Body (14px / SemiBold / height 1.75)
  static const TextStyle bodyStrong = TextStyle(
    fontFamily: fontFamilyArabic,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.75,
    color: PieColors.ink,
  );

  /// Form & Control Label (12px / Medium / height 1.6)
  static const TextStyle label = TextStyle(
    fontFamily: fontFamilyArabic,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    height: 1.6,
    color: PieColors.inkSecondary,
  );

  /// Subtle Caption (11px / Regular / height 1.5)
  static const TextStyle caption = TextStyle(
    fontFamily: fontFamilyArabic,
    fontSize: 11,
    fontWeight: FontWeight.w400,
    height: 1.5,
    color: PieColors.inkMuted,
  );

  // --- Monospace Numeric Styles (Data is tabular) ---

  /// Large numeric hero (e.g. Total net sales, till drawer cash)
  static const TextStyle monoDisplay = TextStyle(
    fontFamily: fontFamilyMono,
    fontSize: 26,
    fontWeight: FontWeight.w600,
    height: 1.3,
    color: PieColors.ink,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// Medium numeric (e.g. Card totals, receipt subtotals)
  static const TextStyle monoHeading = TextStyle(
    fontFamily: fontFamilyMono,
    fontSize: 18,
    fontWeight: FontWeight.w500,
    height: 1.4,
    color: PieColors.ink,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// Standard tabular numeric (e.g. line prices, quantities, stop numbers)
  static const TextStyle monoBody = TextStyle(
    fontFamily: fontFamilyMono,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.5,
    color: PieColors.inkSecondary,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// Small tabular numeric (e.g. timestamps, order refs, SKU tags)
  static const TextStyle monoCaption = TextStyle(
    fontFamily: fontFamilyMono,
    fontSize: 11,
    fontWeight: FontWeight.w400,
    height: 1.4,
    color: PieColors.inkMuted,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  // --- Formatting Helpers ---

  /// Format money in Egyptian Pounds (`ج.م`) with tabular numerals in LTR
  static String formatEgp(num amount, {bool showPoundSymbol = true}) {
    final formatted = amount.toStringAsFixed(2);
    if (!showPoundSymbol) return formatted;
    // Keep numeral LTR-isolated before currency symbol
    return '\u202A$formatted\u202C ج.م';
  }

  /// Format integers with LTR isolation
  static String formatInt(int number) {
    return '\u202A$number\u202C';
  }

  /// Format timers / time strings e.g. "12:45"
  static String formatTime(String time) {
    return '\u202A$time\u202C';
  }
}

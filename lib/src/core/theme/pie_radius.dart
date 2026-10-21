import 'package:flutter/material.dart';

/// PIE 3-tier Corner Radius Ladder
///
/// Jobs / Ive Restraint:
/// Rather than an unprincipled scatter of arbitrary radiuses (4, 8, 10, 12, 16, 20),
/// PIE strictly adheres to a geometric 3-tier ladder:
/// - [sm] (6px): Compact inline elements — status pills, chips, tags, badges.
/// - [md] (10px): Interactive touch controls — buttons, form inputs, steppers, snackbars.
/// - [lg] (14px): Structural surfaces — cards, bottom sheets, dialogs, inspection panels.
abstract final class PieRadius {
  /// 6.0px: Badges, chips, tags, status pills
  static const double sm = 6.0;

  /// 10.0px: Buttons, form input fields, snackbars, stepper controls
  static const double md = 10.0;

  /// 14.0px: Cards, bottom sheets, dialog modals, side inspection sheets
  static const double lg = 14.0;

  static const BorderRadius borderSm = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius borderMd = BorderRadius.all(Radius.circular(md));
  static const BorderRadius borderLg = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius topLg = BorderRadius.vertical(top: Radius.circular(lg));
}

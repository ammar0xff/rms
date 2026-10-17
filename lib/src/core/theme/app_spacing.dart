/// Spacing and radii transcribed from the design files.
///
/// The files set their own scale on two screens (`spacing: space-xs 0.25rem …
/// gutter 0.75rem`) and otherwise ride Tailwind's defaults. Those defaults are
/// what the other 25 screens actually render with, so the values below are the
/// ones measured in the exports rather than a new scheme.
///
/// Radii follow the design's usage counts: `rounded-lg` (8px) 590 uses,
/// `rounded-xl` (12px) 329, `rounded-full` 444, `rounded-2xl` (16px) 37.
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;

  static const double section = 20;
  static const double cardGap = 12;

  /// The screens pad their scroll area `px-4` on phones.
  static const double pagePadding = 16;
  static const double sidebarWidth = 220;

  /// The header in every screen is `h-16`.
  static const double topBarHeight = 64;

  static const double radiusSm = 6;
  static const double radiusMd = 8;
  static const double radiusLg = 12;
  static const double radiusXl = 16;
  static const double radiusPill = 999;
}

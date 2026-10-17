/// Spacing, radii and the header height, transcribed from the project's
/// `designMd`.
///
///   Layout & Spacing — "a strict 4px base step (0.25rem)", "minimum physical
///   hit targets of 44x44px despite compact 4px-8px internal gaps"
///   Shapes — "Base Components 4px · Structural Containers 8px · Pill 9999px"
///   rounded — sm 0.125rem · DEFAULT 0.25rem · md 0.375rem · lg 0.5rem ·
///             xl 0.75rem · full 9999px
abstract final class AppSpacing {
  /// The 4px base step everything else multiplies.
  static const double base = 4;

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;

  static const double section = 16;
  static const double cardGap = 12;

  /// "Full-bleed application canvas with zero unutilized margins" — the page
  /// gutter is the design's `margin-mobile` of 0.75rem.
  static const double pagePadding = 12;

  static const double sidebarWidth = 220;

  /// The header is `h-16` in every generated screen.
  static const double topBarHeight = 64;

  // --- Shapes --------------------------------------------------------------
  // Tight and utilitarian. Only functional corners are rounded.

  /// Base components: buttons, inputs, badges, dropdowns.
  static const double radiusSm = 4;

  /// The default corner — also the structural container radius.
  static const double radiusMd = 8;

  /// Structural containers: tickets, modals, flyout panels.
  static const double radiusLg = 8;

  /// The larger of the two token steps, kept distinct for panels that read
  /// as whole surfaces.
  static const double radiusXl = 12;

  /// Reserved for live operational status pills only.
  static const double radiusPill = 999;

  /// The minimum physical hit target the design mandates.
  static const double touchTarget = 44;
}

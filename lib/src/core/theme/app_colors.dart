import 'package:flutter/material.dart';

/// The Stitch "Industrial Tactile POS" design system.
///
/// Transcribed from the project's own `designMd` — the design document Stitch
/// publishes for this project — not from a hand-reading of the generated HTML.
/// Every value below is quoted from it:
///
///   Colors → Base Surfaces & Boundaries, Typography & Ink Levels,
///   Role-Specific Accents, Offline Engine & Sync States
///   Layout & Spacing → Depth by Tonal Stacking (Levels 0-4)
///   Elevation & Depth → Borders & Dividers
///
/// Note the depths: the design stacks tone, never blur or shadow
/// ("Blur filters and diffused drop shadows are omitted to maintain 60 FPS").
/// Nothing in this file is a gradient.
abstract final class AppColors {
  // --- Depth by Tonal Stacking ------------------------------------------------
  // Level 0 (canvas), 1 (wells), 2 (cards), 3 (controls), 4 (modals).

  /// Level 0 — the page canvas and the master navigation rail.
  static const base = Color(0xFF0A0A0C);

  /// Level 1 — the sunken well: table headers, numeric troughs, keypad backs.
  static const surfaceSunken = Color(0xFF0C0C0E);

  /// Level 2 — cards, tickets, active panels. The workhorse surface.
  static const surface = Color(0xFF101012);

  /// Level 3 — selected items, open popovers, secondary button fill.
  static const surfaceSecondary = Color(0xFF16161A);

  /// Level 4 — system modals and critical overlays.
  static const surfaceBright = Color(0xFF1A1A1E);

  /// The design's remaining secondary surface: sub-cards and drawers.
  static const surfaceDrawer = Color(0xFF0E0E10);

  /// Level 3 again, named for its role as a hover/pressed state.
  static const hover = Color(0xFF16161A);

  // --- Borders & Dividers ---------------------------------------------------
  // "All panel divisions use 1px solid #1A1A1E; dividers between internal
  //  order list items use 1px solid #16161A; active inputs elevate to
  //  1px solid #1E1E22."

  /// Structural hairlines: panels and containers.
  static const borderStrong = Color(0xFF1A1A1E);

  /// Dividers between internal list items.
  static const borderSubtle = Color(0xFF16161A);

  /// The faintest line, used where two containers meet.
  static const borderFaint = Color(0xFF141417);

  /// Control and input hairlines — the elevated step.
  static const control = Color(0xFF1E1E22);

  /// The design's outline tokens, per Typography & Ink Levels.
  static const outline = Color(0xFF71717A);
  static const outlineVariant = Color(0xFF27272A);

  // --- Typography & Ink Levels ----------------------------------------------
  // "High Contrast #FAFAFA · Primary Body #E4E4E7 · Secondary Body #A1A1AA ·
  //  Muted #71717A · Ghost #27272A"

  /// High contrast: totals, key modifiers, warnings.
  static const fg = Color(0xFFFAFAFA);

  /// Reserved for the single brightest element on a surface.
  static const fgBright = Color(0xFFFFFFFF);

  /// Primary body: main content, order IDs.
  static const fgSecondary = Color(0xFFE4E4E7);

  /// Secondary body: labels, metadata, line items.
  static const fgMuted = Color(0xFFA1A1AA);

  /// Muted: micro-copy, inactive keys, timestamps.
  static const fgDim = Color(0xFF71717A);

  /// Ghost: inactive borders, subtle indicators.
  static const fgGhost = Color(0xFF27272A);

  // --- Role-Specific Accents ------------------------------------------------
  // "Cashier Warm Amber #F5A524 · Dispatch/Driver Highway Sky Blue #60A5FA ·
  //  Command/Manager Emerald Green #34D399 · System Core/Admin Deep Violet
  //  #A78BFA · KDS Flame Crimson #EF4444 / Alert Red #F87171"
  //
  // The fifth accent belonged to the kitchen display, which this app no longer
  // has. It survives only as the destructive/error red it doubles as.

  static const cashierAccent = Color(0xFFF5A524);
  static const driverAccent = Color(0xFF60A5FA);
  static const managerAccent = Color(0xFF34D399);
  static const developerAccent = Color(0xFFA78BFA);

  /// The brand accent is the cashier amber: it is the "primary operational
  /// button" fill the design names first, and the app's default role.
  static const brand = Color(0xFFF5A524);

  /// Ink on top of a filled accent. The design specifies #0A0A0C, which is
  /// also the canvas — deliberate, so a filled control reads as an island.
  static const onBrand = Color(0xFF0A0A0C);

  /// Tinted fills derived from an accent, for chips and soft badges.
  static Color accentSoft(Color accent, [double alpha = 0.12]) =>
      accent.withValues(alpha: alpha);

  static const brandSoft = Color(0x1FF5A524);
  static const brandLine = Color(0x4DF5A524);

  // --- Offline Engine & Sync States -----------------------------------------
  // "Local SQLite / Pending Sync: Amber #FBBF24 · Cloud Reconciled / Synced:
  //  Emerald #34D399 · Merge Conflict / Station Late: Red #F87171 ·
  //  Mesh Dispatch / In-Transit: Blue #60A5FA"

  static const warning = Color(0xFFFBBF24);
  static const warningSoft = Color(0x1FFBBF24);

  static const positive = Color(0xFF34D399);
  static const secondary = Color(0xFF34D399);
  static const secondaryContainer = Color(0xFF34D399);
  static const secondarySoft = Color(0x1F34D399);

  /// Alert red, for status the operator must not miss.
  static const negative = Color(0xFFF87171);
  static const negativeSoft = Color(0x1FF87171);

  /// Destructive red, per Components → Destructive / Void Button.
  static const destructive = Color(0xFFEF4444);
  static const negativeContainer = Color(0x33EF4444);
  static const onNegative = Color(0xFFF87171);

  static const info = Color(0xFF60A5FA);
  static const tertiary = Color(0xFF60A5FA);
  static const tertiaryContainer = Color(0xFF60A5FA);
  static const tertiarySoft = Color(0x1F60A5FA);
  static const purple = developerAccent;

  // --- Inverse (tooltips and overlays) --------------------------------------
  static const inverseSurface = Color(0xFFE4E4E7);
  static const inverseOnSurface = Color(0xFF16161A);
  static const inversePrimary = Color(0xFFF5A524);

  /// The accent whose ink is light rather than dark — needed wherever a filled
  /// control carries the violet role accent.
  static bool isLightAccent(Color accent) =>
      accent == developerAccent || accent == managerAccent ||
      accent == driverAccent;
}

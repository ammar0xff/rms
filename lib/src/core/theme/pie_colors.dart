import 'package:flutter/material.dart';
import '../../domain/models/app_role.dart';

/// PIE Tonal Ladder & Color System
///
/// Hostile environment design:
/// - Canvas is deep, near-black with a cool cast to survive sunlight and glare.
/// - The tonal ladder has 6 surfaces engineered for hierarchy.
/// - Exactly one unmistakable accent per role.
/// - Clear semantic colors for sync state and system operations.
abstract final class PieColors {
  // --- Tonal Ladder (Surfaces) ---
  /// Deep near-black canvas with a cool cast (0xFF090A0D)
  static const Color canvas = Color(0xFF090A0E);

  /// Inset well / recessed background (0xFF050608)
  static const Color well = Color(0xFF050608);

  /// Resting card surface (0xFF12141A)
  static const Color surface1 = Color(0xFF12141A);
  static const Color surface = surface1;

  /// Raised card / container surface (0xFF1A1D26)
  static const Color surface2 = Color(0xFF1A1D26);

  /// Active / highlighted control surface (0xFF242834)
  static const Color surface3 = Color(0xFF242834);

  /// Floating overlay / modal / sheet (0xFF1E212B)
  static const Color surfaceOverlay = Color(0xFF1E212B);

  // --- Borders & Separators ---
  /// Hairline structural border (0xFF262A36)
  static const Color border = Color(0xFF262A36);

  /// Subtle inner highlight for raised edges (0xFF3A4052)
  static const Color highlight = Color(0xFF3A4052);

  // --- Ink (Text & Iconography) ---
  /// Genuinely bright primary ink to resist washout (0xFFF8FAFC)
  static const Color ink = Color(0xFFF8FAFC);

  /// Secondary body ink (0xFFCBD5E1) - WCAG AAA compliant
  static const Color inkSecondary = Color(0xFFCBD5E1);

  /// Muted caption & label ink (0xFF94A3B8) - WCAG AA compliant on all surfaces
  static const Color inkMuted = Color(0xFF94A3B8);

  // --- Aliases for developer ergonomics ---
  static const Color textPrimary = ink;
  static const Color textSecondary = inkSecondary;
  static const Color textMuted = inkMuted;
  static const Color borderSubtle = border;
  static const Color borderMuted = border;

  static const Color roleCashier = cashierAccent;
  static const Color roleDriver = driverAccent;
  static const Color roleManager = managerAccent;
  static const Color roleSystem = systemAccent;

  // --- Role Accents ---
  // Cashier: Warm Amber — the till, heat, immediacy
  static const Color cashierAccent = Color(0xFFF59E0B);
  static const Color cashierHover = Color(0xFFFBBF24);
  static const Color cashierSurface = Color(0xFF291B06);
  static const Color cashierBorder = Color(0xFF78350F);

  // Driver: Sky Blue — open road, transit, distance
  static const Color driverAccent = Color(0xFF0EA5E9);
  static const Color driverHover = Color(0xFF38BDF8);
  static const Color driverSurface = Color(0xFF07273C);
  static const Color driverBorder = Color(0xFF0369A1);

  // Manager: Emerald — money, growth, calm control
  static const Color managerAccent = Color(0xFF10B981);
  static const Color managerHover = Color(0xFF34D399);
  static const Color managerSurface = Color(0xFF062D20);
  static const Color managerBorder = Color(0xFF047857);

  // System Admin: Violet — instrumentation, diagnostics, the machine
  static const Color systemAccent = Color(0xFF8B5CF6);
  static const Color systemHover = Color(0xFFA78BFA);
  static const Color systemSurface = Color(0xFF221340);
  static const Color systemBorder = Color(0xFF6D28D9);

  // --- Semantic States (Distinguishable from role accents) ---
  /// Synced with backend / reconciled
  static const Color stateSynced = Color(0xFF14B8A6); // Teal
  static const Color stateSyncedBg = Color(0xFF042F2C);

  /// Local on device only / pending outbox queue
  static const Color statePending = Color(0xFFEAB308); // Ochre
  static const Color statePendingBg = Color(0xFF332502);

  /// Warning state (ochre / amber)
  static const Color stateWarning = statePending;

  /// Data conflict requiring three-way merge
  static const Color stateConflict = Color(0xFFF97316); // Amber-Orange
  static const Color stateConflictBg = Color(0xFF3B1703);

  /// Error, void, failed delivery, destructive action
  static const Color stateError = Color(0xFFEF4444); // Crimson Red
  static const Color stateErrorBg = Color(0xFF380D0D);

  /// Offline mode / network disconnected
  static const Color stateOffline = Color(0xFF64748B); // Slate Grey
  static const Color stateOfflineBg = Color(0xFF1E293B);

  /// Get role accent based on current active role
  static Color accentFor(AppRole role) {
    return switch (role) {
      AppRole.cashier => cashierAccent,
      AppRole.driver => driverAccent,
      AppRole.manager => managerAccent,
      AppRole.developer => systemAccent,
    };
  }

  /// Get role surface based on current active role
  static Color surfaceFor(AppRole role) {
    return switch (role) {
      AppRole.cashier => cashierSurface,
      AppRole.driver => driverSurface,
      AppRole.manager => managerSurface,
      AppRole.developer => systemSurface,
    };
  }

  /// Get role border based on current active role
  static Color borderFor(AppRole role) {
    return switch (role) {
      AppRole.cashier => cashierBorder,
      AppRole.driver => driverBorder,
      AppRole.manager => managerBorder,
      AppRole.developer => systemBorder,
    };
  }
}

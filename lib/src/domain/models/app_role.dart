/// What the signed-in operator may see and do in PIE Operations.
///
/// Roles define clear operational boundaries:
/// - [driver]: Personal active trips, personal cash custody handover, and trip archive.
/// - [cashier]: POS selling, shift drawer sessions, invoices, branch fleet status, and driver custody settlements.
/// - [manager]: Operational dashboard, approvals/voids, inventory, team, and multi-branch transfers.
/// - [developer]: System diagnostics, conflict resolution, releases, and deep internals.
enum AppRole {
  /// Own deliveries, personal collections, and personal stop navigation. Mobile-first.
  driver('طيار', 'الدليفري'),

  /// Sells: POS, cash drawer, invoices, branch fleet oversight, and driver settlement.
  cashier('كاشير', 'الكاشير'),

  /// The whole operation: approvals, inventory, staff, and branches.
  manager('مدير', 'لوحة التحكم'),

  /// Everything, plus system internals (sync center, conflicts, telemetry).
  developer('مسؤول نظام', 'لوحة التحكم');

  const AppRole(this.label, this.homeLabel);

  /// Arabic display label.
  final String label;

  /// Short label for the role's home destination.
  final String homeLabel;

  // --- Granular Permissions (RBAC) ---

  /// Cashiers, managers, and system admins can operate the POS and make sales.
  bool get canSell => this == cashier || this == manager || this == developer;

  /// Cashiers, managers, and system admins manage cash drawer and shift sessions.
  bool get canManageCashDrawer =>
      this == cashier || this == manager || this == developer;

  /// Cashiers, managers, and system admins oversee branch couriers and dispatch.
  bool get canViewBranchDrivers =>
      this == cashier || this == manager || this == developer;

  /// Cashiers can collect returned cash custody from couriers into the till.
  bool get canSettleDriverCustody =>
      this == cashier || this == manager || this == developer;

  /// Only couriers perform active delivery trips and individual stop delivery.
  bool get isDriver => this == driver;

  /// Managers and developers may approve refunds, discounts, and petty cash.
  bool get canApproveRequests => this == manager || this == developer;

  /// Managers and developers can audit stock and record adjustments/purchases.
  bool get canManageInventory => this == manager || this == developer;

  /// Managers and developers may view and manage team members and shifts.
  bool get canManageTeam => this == manager || this == developer;

  /// Managers and developers can manage branch nodes and initiate transfers.
  bool get canManageBranches => this == manager || this == developer;

  /// Developers and managers can access system diagnostics and node status.
  bool get canViewDiagnostics => this == developer || this == manager;

  /// Only system administrators/developers can resolve sync conflicts.
  bool get canResolveConflicts => this == developer;

  /// Privileged roles can manage settings, override workflows, and inspect logs.
  bool get isPrivileged => this == manager || this == developer;

  /// Robust, case-insensitive parser mapping domain names, abbreviations,
  /// and Arabic role titles to their respective [AppRole].
  static AppRole? tryParse(Object? value) {
    if (value is! String) return null;
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) return null;

    // Direct name match
    for (final role in AppRole.values) {
      if (role.name.toLowerCase() == normalized) return role;
    }

    // Courier / Driver aliases
    if (normalized == 'pilot' ||
        normalized == 'courier' ||
        normalized == 'delivery' ||
        normalized == 'طيار' ||
        normalized == 'دليفري' ||
        normalized == 'سائق' ||
        normalized == 'كابتن') {
      return AppRole.driver;
    }

    // Cashier aliases
    if (normalized == 'cahier' ||
        normalized == 'teller' ||
        normalized == 'pos' ||
        normalized == 'كاشير' ||
        normalized == 'صراف' ||
        normalized == 'نقطة بيع') {
      return AppRole.cashier;
    }

    // Manager aliases
    if (normalized == 'admin_branch' ||
        normalized == 'supervisor' ||
        normalized == 'gm' ||
        normalized == 'مدير' ||
        normalized == 'مشرف' ||
        normalized == 'إدارة') {
      return AppRole.manager;
    }

    // Developer / System Admin aliases
    if (normalized == 'admin' ||
        normalized == 'dev' ||
        normalized == 'system_admin' ||
        normalized == 'superadmin' ||
        normalized == 'root' ||
        normalized == 'مطوّر' ||
        normalized == 'مسؤول نظام' ||
        normalized == 'مسؤول' ||
        normalized == 'ادمن') {
      return AppRole.developer;
    }

    return null;
  }
}

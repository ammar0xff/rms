/// What the signed-in operator may see and do.
///
/// The role comes from the `users/{uid}` document in Firebase mode
/// (`roleFor`), or from the email convention in demo mode. Unknown and
/// unreadable roles fall back to [cashier]: the operational middle — narrower
/// than manager, useful unlike a locked-out stub.
///
/// Roles are additive upward in practice (manager sees what a cashier sees),
/// but the shell defines the exact navigation sets, not this enum.
enum AppRole {
  /// Own deliveries, collections, and personal queue. Mobile-first.
  driver('طيار', 'الدليفري'),

  /// Sells: POS, customers, and the dashboard. The default when a role cannot
  /// be determined.
  cashier('كاشير', 'الكاشير'),

  /// Kitchen display and the menu it cooks from.
  chef('شيف', 'المطبخ'),

  /// The whole operation except explicitly developer system screens.
  manager('مدير', 'لوحة التحكم'),

  /// Everything, plus system internals (sync center, conflicts, team).
  developer('مطوّر', 'لوحة التحكم');

  const AppRole(this.label, this.homeLabel);

  /// Arabic display label.
  final String label;

  /// Short label for the role's home destination.
  final String homeLabel;

  /// Managers and developers may acknowledge stuck work and manage the team.
  bool get isPrivileged => this == manager || this == developer;

  static AppRole? tryParse(Object? value) {
    if (value is! String) return null;
    for (final role in AppRole.values) {
      if (role.name == value) return role;
    }
    return null;
  }
}

import 'app_role.dart';

/// Fine-grained POS permissions stored on `users/{uid}` as a string list.
/// Roles stay the coarse gate (shell, team screen); permissions refine
/// individual actions. Absent list means role defaults — never a lockout.
abstract final class Permissions {
  static const menuEdit = 'menu.edit';
  static const orderDiscount = 'order.discount';
  static const orderVoid = 'order.void';
  static const paymentReprint = 'payment.reprint';

  static const all = [menuEdit, orderDiscount, orderVoid, paymentReprint];

  static const Map<String, String> labels = {
    menuEdit: 'تعديل القائمة',
    orderDiscount: 'طلب خصم',
    orderVoid: 'طلب إلغاء فاتورة',
    paymentReprint: 'إعادة طباعة',
  };

  /// Role defaults used when the user document has no explicit list.
  static Set<String> defaultsFor(AppRole role) => switch (role) {
        AppRole.manager || AppRole.developer => Set.of(all),
        AppRole.cashier => {orderVoid, paymentReprint},
        AppRole.driver => {},
      };

  static Set<String> parse(Object? value, AppRole role) {
    if (value is! List) return defaultsFor(role);
    final explicit = {
      for (final e in value)
        if (e is String && all.contains(e)) e,
    };
    // Explicit list replaces defaults entirely (empty means nothing).
    return explicit;
  }
}

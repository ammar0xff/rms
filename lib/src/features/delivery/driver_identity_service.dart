import '../../domain/models/app_user.dart';
import '../../domain/models/delivery.dart';

/// Manages and resolves the authenticated driver's operational identity.
///
/// Ensures each courier in the field strictly sees their own assigned deliveries,
/// their own cash custody, and their personal shift log.
class DriverSession {
  DriverSession._();
  static final DriverSession instance = DriverSession._();

  String? _activeDriverName;

  /// Explicitly chosen courier name (e.g. selected in DriverProfileScreen or on shared terminal).
  String? get activeDriverName => _activeDriverName;

  set activeDriverName(String? name) {
    _activeDriverName = (name != null && name.trim().isNotEmpty) ? name.trim() : null;
  }

  /// Resolves the current courier's name matching [DeliveryModel.driver].
  String resolveCurrentDriverName({
    required AppUser? user,
    required List<DriverModel> drivers,
  }) {
    if (_activeDriverName != null && _activeDriverName!.isNotEmpty) {
      return _activeDriverName!;
    }

    if (user != null) {
      final displayName = user.displayName?.trim() ?? '';
      if (displayName.isNotEmpty) {
        for (final d in drivers) {
          if (d.name.toLowerCase() == displayName.toLowerCase()) {
            return d.name;
          }
        }
        return displayName;
      }

      final emailLocal = (user.email ?? '').trim().toLowerCase().split('@').first;
      if (emailLocal.isNotEmpty) {
        // Explicit match for default pilot account (driver@pie.eg)
        if (emailLocal == 'driver' || (user.email?.toLowerCase().trim() == 'driver@pie.eg')) {
          for (final d in drivers) {
            if (d.name == 'كابتن توصيل' || d.name.contains('توصيل')) {
              return d.name;
            }
          }
          return 'كابتن توصيل';
        }

        for (final d in drivers) {
          final dLower = d.name.toLowerCase();
          if (emailLocal == dLower ||
              emailLocal.contains(dLower) ||
              dLower.contains(emailLocal)) {
            return d.name;
          }
        }

        // Clean common prefixes (driver, pilot, courier)
        final cleaned = emailLocal
            .replaceAll('driver', '')
            .replaceAll('pilot', '')
            .replaceAll('courier', '')
            .replaceAll(RegExp(r'^[._-]+|[._-]+$'), '');
        if (cleaned.isNotEmpty) {
          return 'كابتن $cleaned';
        }
      }
    }

    if (drivers.isNotEmpty) {
      return drivers.first.name;
    }

    return 'كابتن التوصيل';
  }
}

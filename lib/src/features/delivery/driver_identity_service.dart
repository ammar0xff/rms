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
      // 1. Direct ID match: user.uid matches DriverModel.id
      for (final d in drivers) {
        if (d.id == user.uid && d.name.isNotEmpty) {
          return d.name;
        }
      }

      // 2. Direct email match: user.email matches DriverModel.email
      final userEmail = user.email?.trim().toLowerCase() ?? '';
      if (userEmail.isNotEmpty) {
        for (final d in drivers) {
          if (d.email.isNotEmpty && d.email.trim().toLowerCase() == userEmail && d.name.isNotEmpty) {
            return d.name;
          }
        }
      }

      // 3. Display name match
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
          if (drivers.isNotEmpty) {
            return drivers.first.name;
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

  /// Checks whether a [DeliveryModel] belongs to the currently active or authenticated courier.
  bool isDeliveryAssignedToCurrentDriver({
    required DeliveryModel delivery,
    required AppUser? user,
    required List<DriverModel> drivers,
  }) {
    final assigned = delivery.driver.trim();
    if (assigned.isEmpty || assigned == DeliveryModel.unassignedDriver) return false;

    final myName = resolveCurrentDriverName(user: user, drivers: drivers);
    if (assigned.toLowerCase() == myName.toLowerCase()) return true;

    // Resolve matching driver model for current user
    DriverModel? myDriverModel;
    if (user != null) {
      for (final d in drivers) {
        if (d.id == user.uid ||
            (d.email.isNotEmpty && d.email.toLowerCase() == (user.email ?? '').toLowerCase()) ||
            d.name.toLowerCase() == myName.toLowerCase()) {
          myDriverModel = d;
          break;
        }
      }
    }

    if (myDriverModel != null) {
      if (assigned.toLowerCase() == myDriverModel.name.toLowerCase()) return true;
      if (assigned.toLowerCase() == myDriverModel.id.toLowerCase()) return true;
      if (myDriverModel.email.isNotEmpty &&
          assigned.toLowerCase() == myDriverModel.email.toLowerCase()) {
        return true;
      }
    }

    if (user != null) {
      if (user.displayName != null &&
          assigned.toLowerCase() == user.displayName!.trim().toLowerCase()) {
        return true;
      }
      if (user.email != null &&
          assigned.toLowerCase() == user.email!.trim().toLowerCase()) {
        return true;
      }
      if (assigned.toLowerCase() == user.uid.trim().toLowerCase()) {
        return true;
      }
    }

    return false;
  }
}

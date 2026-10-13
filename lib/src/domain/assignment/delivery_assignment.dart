import '../models/delivery.dart';

/// One provisional assignment produced by [DeliveryAssignmentPolicy].
class PlannedAssignment {
  const PlannedAssignment({required this.deliveryId, required this.driver});

  final String deliveryId;

  /// Driver *name*, matching [DeliveryModel.driver] and [DriverModel.name].
  final String driver;
}

/// Deterministic, offline-safe driver assignment planner.
///
/// Driver assignment is normally server-authoritative. This policy only ever
/// produces a *provisional* plan that the device may apply when the server has
/// explicitly permitted local auto-assignment (see [autoAssignFlagKey]); the
/// backend remains the source of truth and reconciles the assignment later.
///
/// The plan is a pure function of the cached roster and the open jobs: it only
/// considers [DriverModel.available] couriers, always prefers the least-loaded
/// one, and breaks ties by name (then id). Two offline terminals holding the
/// same roster therefore compute the same assignments, and the same inputs
/// always yield the same result, which keeps the behaviour testable.
abstract final class DeliveryAssignmentPolicy {
  /// The server-managed flag that permits provisional local auto-assignment.
  static const String autoAssignFlagKey = 'delivery_auto_assign';

  /// Chooses the least-loaded available driver for a single job, or null when
  /// no courier is available.
  static String? pickDriver({
    required List<DeliveryModel> deliveries,
    required List<DriverModel> drivers,
  }) {
    final available = _availableDrivers(drivers);
    if (available.isEmpty) return null;
    final load = _loads(deliveries, available);
    return _leastLoaded(available, load).name;
  }

  /// Plans an assignment for every waiting job, oldest first, spreading the
  /// work across the available couriers as evenly as possible.
  static List<PlannedAssignment> plan({
    required List<DeliveryModel> deliveries,
    required List<DriverModel> drivers,
  }) {
    final available = _availableDrivers(drivers);
    if (available.isEmpty) return const [];

    final load = _loads(deliveries, available);
    final waiting = deliveries
        .where((d) => d.state == DeliveryState.waiting)
        .toList()
      ..sort((a, b) {
        final byTime = a.createdAt.compareTo(b.createdAt);
        return byTime != 0 ? byTime : a.id.compareTo(b.id);
      });

    final planned = <PlannedAssignment>[];
    for (final job in waiting) {
      final driver = _leastLoaded(available, load);
      load[driver.name] = (load[driver.name] ?? 0) + 1;
      planned.add(PlannedAssignment(deliveryId: job.id, driver: driver.name));
    }
    return planned;
  }

  /// Available couriers, ordered by name then id so ties are deterministic.
  static List<DriverModel> _availableDrivers(List<DriverModel> drivers) =>
      drivers.where((d) => d.available).toList()
        ..sort((a, b) {
          final byName = a.name.compareTo(b.name);
          return byName != 0 ? byName : a.id.compareTo(b.id);
        });

  /// Counts the open jobs already assigned to each available courier.
  static Map<String, int> _loads(
    List<DeliveryModel> deliveries,
    List<DriverModel> available,
  ) {
    final load = <String, int>{for (final d in available) d.name: 0};
    for (final delivery in deliveries) {
      if (!delivery.state.isOpen) continue;
      final current = load[delivery.driver];
      if (current != null) load[delivery.driver] = current + 1;
    }
    return load;
  }

  /// The first of [available] with the fewest current jobs. [available] is
  /// pre-sorted, so equal loads keep the lowest name (then id).
  static DriverModel _leastLoaded(
    List<DriverModel> available,
    Map<String, int> load,
  ) {
    var best = available.first;
    var bestLoad = load[best.name] ?? 0;
    for (final driver in available.skip(1)) {
      final driverLoad = load[driver.name] ?? 0;
      if (driverLoad < bestLoad) {
        best = driver;
        bestLoad = driverLoad;
      }
    }
    return best;
  }
}

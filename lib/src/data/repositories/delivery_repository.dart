import '../../domain/models/collection.dart';
import '../../domain/models/delivery.dart';
import '../../domain/models/payment.dart';

/// Result of attempting to assign a driver while offline.
///
/// [conflict] means the caller's snapshot was stale (another device/actor had
/// already reassigned the job), so the reassignment was recorded as a conflict
/// for review instead of silently overwriting the newer assignment.
enum AssignmentOutcome { assigned, conflict }

/// One provisional assignment produced by
/// [DeliveryRepository.autoAssignWaiting], reporting the driver chosen and
/// whether the write was applied or flagged as a conflict.
class DeliveryAssignmentResult {
  const DeliveryAssignmentResult({
    required this.deliveryId,
    required this.driver,
    required this.outcome,
  });

  final String deliveryId;
  final String driver;
  final AssignmentOutcome outcome;
}

/// Local-first access to delivery jobs, the courier roster, and the append-only
/// collection log.
abstract class DeliveryRepository {
  Future<List<DeliveryModel>> listDeliveries();

  Future<List<DriverModel>> listDrivers();

  Future<void> cacheDrivers(List<DriverModel> drivers, {bool replace = true});

  /// Creates a job for a newly placed delivery order and returns it.
  Future<DeliveryModel> createDelivery({
    required String orderRef,
    required String address,
    required double amount,
    bool createdOffline = false,
  });

  /// Assigns [driver] to a job.
  ///
  /// When [baseDriver] is supplied, it is the driver the caller last observed:
  /// if the stored job already carries a different driver, the reassignment is
  /// recorded as a conflict instead of applied.
  Future<AssignmentOutcome> assignDriver(
    String deliveryId,
    String driver, {
    String? baseDriver,
    String? reason,
  });

  /// Provisional, offline-safe auto-assignment of every waiting job.
  ///
  /// When the server has explicitly permitted local auto-assignment (the
  /// `delivery_auto_assign` flag), the device picks the least-loaded available
  /// driver for each unassigned job, oldest first, and applies the whole batch
  /// in a single transaction. The backend stays authoritative: it reconciles
  /// these provisional assignments later, and a stale reassignment is still
  /// recorded as a conflict rather than silently applied.
  ///
  /// Returns one result per job that was planned; an empty list means there was
  /// nothing to assign or no courier was available.
  Future<List<DeliveryAssignmentResult>> autoAssignWaiting();

  Future<void> updateState(String deliveryId, DeliveryState state);

  /// Marks an en-route stop failed with a mandatory reason. The COD leaves
  /// the queue with it — no collection is ever recorded for a failed stop.
  Future<void> failDelivery(
      String deliveryId, DeliveryFailureReason reason);

  /// Closes the return leg: the bag is back at the branch.
  Future<void> returnToBranch(String deliveryId);

  /// Append-only log of money collected on deliveries.
  Future<List<CollectionModel>> listCollections();

  /// Records a collection for a delivered job. Returns null when the job does
  /// not exist, is not delivered, or already has a collection (recording is
  /// idempotent per job).
  Future<CollectionModel?> recordCollection({
    required String deliveryId,
    required double amount,
    PaymentMethod method = PaymentMethod.cash,
    bool createdOffline = false,
  });

  /// Queues an online settlement command for a delivered job. The settlement is
  /// confirmed only when the backend acknowledges it.
  Future<void> finalizeSettlement(String deliveryId);
}

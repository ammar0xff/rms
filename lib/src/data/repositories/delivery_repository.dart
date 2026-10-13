import '../../domain/models/collection.dart';
import '../../domain/models/delivery.dart';
import '../../domain/models/payment.dart';

/// Result of attempting to assign a driver while offline.
///
/// [conflict] means the caller's snapshot was stale (another device/actor had
/// already reassigned the job), so the reassignment was recorded as a conflict
/// for review instead of silently overwriting the newer assignment.
enum AssignmentOutcome { assigned, conflict }

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
  });

  Future<void> updateState(String deliveryId, DeliveryState state);

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

import '../../domain/models/delivery.dart';

/// Local-first access to delivery jobs and the courier roster.
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

  Future<void> assignDriver(String deliveryId, String driver);

  Future<void> updateState(String deliveryId, DeliveryState state);
}

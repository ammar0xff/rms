import '../../data/local/outbox/outbox_status.dart';

/// Lifecycle of a delivery job, from creation to cash collected.
enum DeliveryState {
  waiting('بانتظار الاستلام'),
  assigned('مُسند'),
  onRoute('في الطريق'),
  delivered('تم التسليم'),
  collected('تم التحصيل');

  const DeliveryState(this.label);

  final String label;

  bool get isOpen =>
      this == DeliveryState.waiting ||
      this == DeliveryState.assigned ||
      this == DeliveryState.onRoute;
}

/// A delivery job attached to an order and (optionally) a driver.
class DeliveryModel {
  DeliveryModel({
    required this.id,
    required this.orderRef,
    required this.address,
    required this.amount,
    required this.state,
    required this.createdAt,
    this.driver = unassignedDriver,
    this.offline = false,
    this.syncStatus = SyncStatus.pendingSync,
  });

  static const String unassignedDriver = 'غير مُسند';

  final String id;
  final String orderRef;
  final String address;
  final double amount;
  final DateTime createdAt;

  String driver;
  DeliveryState state;

  /// Whether this job was created while the device was offline.
  bool offline;
  SyncStatus syncStatus;

  bool get isUnassigned => driver.isEmpty || driver == unassignedDriver;

  Map<String, Object?> toRecord() => {
        'id': id,
        'orderRef': orderRef,
        'address': address,
        'amount': amount,
        'state': state.name,
        'createdAt': createdAt.toIso8601String(),
        'driver': driver,
        'offline': offline,
        'syncStatus': syncStatus.name,
      };

  static DeliveryModel fromRecord(Map<String, Object?> record) => DeliveryModel(
        id: record['id'] as String,
        orderRef: record['orderRef'] as String,
        address: record['address'] as String,
        amount: (record['amount'] as num).toDouble(),
        state: DeliveryState.values.byName(record['state'] as String),
        createdAt: DateTime.parse(record['createdAt'] as String),
        driver: record['driver'] as String? ?? unassignedDriver,
        offline: record['offline'] as bool? ?? false,
        syncStatus: SyncStatus.values.byName(record['syncStatus'] as String),
      );
}

/// A courier available for delivery assignment.
class DriverModel {
  const DriverModel({
    required this.id,
    required this.name,
    this.available = true,
  });

  final String id;
  final String name;
  final bool available;

  Map<String, Object?> toRecord() => {
        'id': id,
        'name': name,
        'available': available,
      };

  static DriverModel fromRecord(Map<String, Object?> record) => DriverModel(
        id: record['id'] as String,
        name: record['name'] as String,
        available: record['available'] as bool? ?? true,
      );
}

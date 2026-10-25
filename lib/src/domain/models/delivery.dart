import '../../data/local/outbox/outbox_status.dart';
import 'collection.dart';
export 'collection.dart';

/// Operational lifecycle of a delivery job.
///
/// This is intentionally *only* the operational state. Money collection and
/// back-office settlement live on [CollectionModel] and [SettlementStatus], so a
/// delivered order is never conflated with a financially settled one.
enum DeliveryState {
  waiting('مستني الاستلام'),
  assigned('مُسند'),
  onRoute('في الطريق'),
  delivered('اتسلّم'),
  failed('اتعثر التسليم'),
  returned('رجع الفرع');

  const DeliveryState(this.label);

  final String label;

  bool get isOpen =>
      this == DeliveryState.waiting ||
      this == DeliveryState.assigned ||
      this == DeliveryState.onRoute;

  bool get isDelivered => this == DeliveryState.delivered;

  /// A failed stop leaves the queue; only the return leg follows it.
  bool get isFailed => this == DeliveryState.failed;
}

/// Why a stop could not complete. Mandatory on the failed transition —
/// the dispatcher and the audit trail both read it.
enum DeliveryFailureReason {
  noAnswer('مابيردّش'),
  wrongAddress('عنوان غلط'),
  refused('رفض الاستلام'),
  cashIssue('مشكلة كاش'),
  breakdown('عطل');

  const DeliveryFailureReason(this.label);

  final String label;
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
    this.customerName,
    this.customerPhone,
    this.landmark,
    this.zoneName,
    this.zoneFee,
    this.offline = false,
    this.settlementStatus = SettlementStatus.pending,
    this.localRevision = 1,
    this.syncStatus = SyncStatus.pendingSync,
    this.failedReason,
    this.failedAt,
  });

  static const String unassignedDriver = 'غير مُسند';

  final String id;
  final String orderRef;
  final String address;
  final double amount;
  final DateTime createdAt;

  String driver;
  DeliveryState state;

  /// Optional customer identity and contact info for the courier in transit.
  final String? customerName;
  final String? customerPhone;
  final String? landmark;

  /// Regional delivery zone name and static fee configured by manager.
  final String? zoneName;
  final double? zoneFee;

  /// Whether this job was created while the device was offline.
  bool offline;

  /// Reconciliation state of the money collected for this job. Advanced only by
  /// a server acknowledgement, never by the device that took the money.
  SettlementStatus settlementStatus;

  /// Monotonic local revision, used as the optimistic-concurrency base for
  /// conflict-aware reassignment.
  int localRevision;

  SyncStatus syncStatus;

  /// Set on the failed transition, cleared never (audit trail). Failed COD
  /// never enters custody because no collection is recorded for it.
  DeliveryFailureReason? failedReason;
  DateTime? failedAt;

  bool get isUnassigned => driver.isEmpty || driver == unassignedDriver;

  Map<String, Object?> toRecord() => {
        'id': id,
        'orderRef': orderRef,
        'address': address,
        'amount': amount,
        'state': state.name,
        'createdAt': createdAt.toIso8601String(),
        'driver': driver,
        'customerName': customerName,
        'customerPhone': customerPhone,
        'landmark': landmark,
        'zoneName': zoneName,
        'zoneFee': zoneFee,
        'offline': offline,
        'settlementStatus': settlementStatus.name,
        'localRevision': localRevision,
        'syncStatus': syncStatus.name,
        'failedReason': failedReason?.name,
        'failedAt': failedAt?.toIso8601String(),
      };

  static DeliveryModel fromRecord(Map<String, Object?> record) => DeliveryModel(
        id: record['id'] as String,
        orderRef: record['orderRef'] as String,
        address: record['address'] as String,
        amount: (record['amount'] as num).toDouble(),
        state: DeliveryState.values.byName(record['state'] as String),
        createdAt: DateTime.parse(record['createdAt'] as String),
        driver: record['driver'] as String? ?? unassignedDriver,
        customerName: record['customerName'] as String?,
        customerPhone: record['customerPhone'] as String?,
        landmark: record['landmark'] as String?,
        zoneName: record['zoneName'] as String?,
        zoneFee: (record['zoneFee'] as num?)?.toDouble(),
        offline: record['offline'] as bool? ?? false,
        settlementStatus: SettlementStatus.values
            .byName(record['settlementStatus'] as String? ?? 'pending'),
        localRevision: (record['localRevision'] as int?) ?? 1,
        syncStatus: SyncStatus.values.byName(record['syncStatus'] as String),
        failedReason: record['failedReason'] == null
            ? null
            : DeliveryFailureReason.values
                .byName(record['failedReason'] as String),
        failedAt: record['failedAt'] == null
            ? null
            : DateTime.parse(record['failedAt'] as String),
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
        id: (record['id'] ?? record['uid'] ?? '') as String,
        name: (record['name'] ?? record['displayName'] ?? record['email'] ?? 'كابتن توصيل') as String,
        available: record['available'] as bool? ?? true,
      );
}

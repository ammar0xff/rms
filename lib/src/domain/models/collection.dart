import '../../data/local/outbox/outbox_status.dart';
import 'payment.dart';

/// Financial settlement status, kept deliberately separate from the
/// operational [DeliveryState] so a delivered order is never implicitly treated
/// as paid, and a recorded collection is never implicitly treated as settled.
enum SettlementStatus {
  pending('قيد التسوية'),
  settled('مُسوّى');

  const SettlementStatus(this.label);

  final String label;
}

/// An append-only record of money collected on a delivery.
///
/// Collections are never edited or deleted — a correction is a new entry — so
/// replaying a sync batch can only ever add rows, never mutate them. This is
/// what makes offline delivery collections traceable without allowing a
/// collection to be silently duplicated: the outbox idempotency key is the
/// server-side dedupe, and only a server acknowledgement can settle it.
class CollectionModel {
  CollectionModel({
    required this.id,
    required this.deliveryId,
    required this.orderRef,
    required this.driver,
    required this.amount,
    required this.method,
    required this.collectedAt,
    this.settledAt,
    this.createdOffline = false,
    this.settlementStatus = SettlementStatus.pending,
    this.syncStatus = SyncStatus.pendingSync,
  });

  final String id;
  final String deliveryId;
  final String orderRef;
  final String driver;
  final double amount;
  final PaymentMethod method;
  final DateTime collectedAt;
  DateTime? settledAt;

  /// Whether this collection was recorded while the device was offline.
  final bool createdOffline;

  SettlementStatus settlementStatus;
  SyncStatus syncStatus;

  Map<String, Object?> toRecord() => {
        'id': id,
        'deliveryId': deliveryId,
        'orderRef': orderRef,
        'driver': driver,
        'amount': amount,
        'method': method.name,
        'collectedAt': collectedAt.toIso8601String(),
        if (settledAt != null) 'settledAt': settledAt!.toIso8601String(),
        'createdOffline': createdOffline,
        'settlementStatus': settlementStatus.name,
        'syncStatus': syncStatus.name,
      };

  static CollectionModel fromRecord(Map<String, Object?> record) =>
      CollectionModel(
        id: (record['id'] ?? '') as String,
        deliveryId: (record['deliveryId'] ?? '') as String,
        orderRef: (record['orderRef'] ?? '') as String,
        driver: (record['driver'] ?? '') as String,
        amount: (record['amount'] as num?)?.toDouble() ?? 0.0,
        method: () {
          final s = record['method'] as String?;
          if (s == null) return PaymentMethod.cash;
          try {
            return PaymentMethod.values.byName(s);
          } catch (_) {
            return PaymentMethod.cash;
          }
        }(),
        collectedAt: record['collectedAt'] == null
            ? DateTime.now()
            : (DateTime.tryParse(record['collectedAt'].toString()) ?? DateTime.now()),
        settledAt: record['settledAt'] != null
            ? DateTime.tryParse(record['settledAt'].toString())
            : null,
        createdOffline: record['createdOffline'] as bool? ?? false,
        settlementStatus: () {
          final s = record['settlementStatus'] as String?;
          if (s == null) return SettlementStatus.pending;
          try {
            return SettlementStatus.values.byName(s);
          } catch (_) {
            return SettlementStatus.pending;
          }
        }(),
        syncStatus: () {
          final s = record['syncStatus'] as String?;
          if (s == null) return SyncStatus.synced;
          try {
            return SyncStatus.values.byName(s);
          } catch (_) {
            return SyncStatus.synced;
          }
        }(),
      );
}

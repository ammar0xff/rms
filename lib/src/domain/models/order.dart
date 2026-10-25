import '../../data/local/outbox/outbox_status.dart';
import 'order_type.dart';

class Order {
  Order({
    required this.localId,
    required this.provisionalOrderNumber,
    required this.items,
    required this.createdOffline,
    required this.createdAt,
    this.orderType = OrderType.takeaway,
    this.taxAmount = 0.0,
    this.discountAmount = 0.0,
    this.serviceAmount = 0.0,
    this.deliveryFee = 0.0,
    this.customerId,
    this.customerName,
    this.customerPhone,
    this.deliveryAddress,
    this.deliveryLatitude,
    this.deliveryLongitude,
    this.branchId,
    this.serverId,
    this.canonicalOrderNumber,
    this.localRevision = 1,
    this.serverRevision,
    this.syncStatus = SyncStatus.localOnly,
    this.voided = false,
    this.voidReason,
  });

  final String localId;
  final String provisionalOrderNumber;
  final List<OrderItem> items;
  final bool createdOffline;
  final DateTime createdAt;
  final OrderType orderType;
  final double deliveryFee;
  final String? customerId;
  final String? customerName;
  final String? customerPhone;
  final String? deliveryAddress;
  final double? deliveryLatitude;
  final double? deliveryLongitude;
  final String? branchId;

  /// Tax charged on top of the items, rounded to cents at creation. Stored on
  /// the order (rather than recomputed at each reader) so the payment, the
  /// delivery amount, the receipt and the sync payload all use one total: the
  /// cart used to charge tax while every record downstream ignored it, so a
  /// payment never matched its order.
  final double taxAmount;

  /// Loyalty/VIP/goodwill reductions and dine-in service charges. Both
  /// default to zero, so every existing total is unchanged until the POS
  /// starts setting them.
  final double discountAmount;
  final double serviceAmount;
  String? serverId;
  String? canonicalOrderNumber;
  int localRevision;
  int? serverRevision;
  SyncStatus syncStatus;

  /// A voided order stays in the ledger (audit trail) but counts for
  /// nothing: totals, kitchen, and delivery all skip it. Voiding goes
  /// through a manager approval, never a delete.
  bool voided;
  String? voidReason;

  double get subtotal =>
      items.fold(0, (sum, item) => sum + item.unitPrice * item.quantity);

  double get total =>
      subtotal - discountAmount + taxAmount + serviceAmount + deliveryFee;

  String get id => serverId ?? localId;
  String get orderNumber => (canonicalOrderNumber != null && canonicalOrderNumber!.isNotEmpty)
      ? canonicalOrderNumber!
      : provisionalOrderNumber;

  Map<String, Object?> toRecord() => {
        'localId': localId,
        'provisionalOrderNumber': provisionalOrderNumber,
        'items': items.map((i) => i.toRecord()).toList(),
        'createdOffline': createdOffline,
        'createdAt': createdAt.toIso8601String(),
        'orderType': orderType.name,
        'taxAmount': taxAmount,
        'discountAmount': discountAmount,
        'serviceAmount': serviceAmount,
        'deliveryFee': deliveryFee,
        'customerId': customerId,
        'customerName': customerName,
        'customerPhone': customerPhone,
        'deliveryAddress': deliveryAddress,
        'deliveryLatitude': deliveryLatitude,
        'deliveryLongitude': deliveryLongitude,
        'branchId': branchId,
        'serverId': serverId,
        'canonicalOrderNumber': canonicalOrderNumber,
        'localRevision': localRevision,
        'voided': voided,
        'voidReason': voidReason,
        'serverRevision': serverRevision,
        'syncStatus': syncStatus.name,
      };

  static Order fromRecord(Map<String, Object?> record) => Order(
        localId: (record['localId'] ?? record['id'] ?? '') as String,
        provisionalOrderNumber: (record['provisionalOrderNumber'] ?? '') as String,
        items: ((record['items'] as List?) ?? [])
            .map((e) => OrderItem.fromRecord(Map<String, Object?>.from(e as Map)))
            .toList(),
        createdOffline: record['createdOffline'] as bool? ?? false,
        createdAt: record['createdAt'] == null
            ? DateTime.fromMillisecondsSinceEpoch(0)
            : (DateTime.tryParse(record['createdAt'].toString()) ?? DateTime.fromMillisecondsSinceEpoch(0)),
        orderType: () {
          final s = record['orderType'] as String?;
          if (s == null) return OrderType.takeaway;
          try {
            return OrderType.values.byName(s);
          } catch (_) {
            return OrderType.takeaway;
          }
        }(),
        taxAmount: (record['taxAmount'] as num?)?.toDouble() ?? 0.0,
        discountAmount: (record['discountAmount'] as num?)?.toDouble() ?? 0.0,
        serviceAmount: (record['serviceAmount'] as num?)?.toDouble() ?? 0.0,
        deliveryFee: (record['deliveryFee'] as num?)?.toDouble() ?? 0.0,
        customerId: record['customerId'] as String?,
        customerName: record['customerName'] as String?,
        customerPhone: record['customerPhone'] as String?,
        deliveryAddress: record['deliveryAddress'] as String?,
        deliveryLatitude: (record['deliveryLatitude'] as num?)?.toDouble(),
        deliveryLongitude: (record['deliveryLongitude'] as num?)?.toDouble(),
        branchId: record['branchId'] as String?,
        serverId: record['serverId'] as String?,
        canonicalOrderNumber: record['canonicalOrderNumber'] as String?,
        localRevision: record['localRevision'] as int? ?? 1,
        voided: record['voided'] as bool? ?? false,
        voidReason: record['voidReason'] as String?,
        serverRevision: record['serverRevision'] as int?,
        syncStatus: () {
          final s = record['syncStatus'] as String?;
          if (s == null) return SyncStatus.pendingSync;
          try {
            return SyncStatus.values.byName(s);
          } catch (_) {
            return SyncStatus.pendingSync;
          }
        }(),
      );
}

class OrderItem {
  const OrderItem({
    required this.productId,
    required this.name,
    required this.unitPrice,
    required this.quantity,
    this.station = '',
    this.note,
    this.modifiers = const [],
  });

  final String productId;
  final String name;
  final double unitPrice;
  final int quantity;

  /// The kitchen station that prepares this line, used to route tickets.
  final String station;

  /// Free-text kitchen note (بدون بصل، محمص كويس). Prints on the ticket.
  final String? note;

  /// Chosen modifier names (دبل، شيدر). Priced into unitPrice already;
  /// carried for the ticket and the archive.
  final List<String> modifiers;

  Map<String, Object?> toRecord() => {
        'productId': productId,
        'name': name,
        'unitPrice': unitPrice,
        'quantity': quantity,
        if (station.isNotEmpty) 'station': station,
        if (note != null && note!.isNotEmpty) 'note': note,
        if (modifiers.isNotEmpty) 'modifiers': modifiers,
      };

  static OrderItem fromRecord(Map<String, Object?> record) => OrderItem(
        productId: (record['productId'] ?? '') as String,
        name: (record['name'] ?? '') as String,
        unitPrice: (record['unitPrice'] as num?)?.toDouble() ?? 0.0,
        quantity: (record['quantity'] as num?)?.toInt() ?? 1,
        station: record['station'] as String? ?? '',
        note: record['note'] as String?,
        modifiers: ((record['modifiers'] as List?) ?? [])
            .map((e) => e.toString())
            .toList(),
      );
}

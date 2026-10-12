import '../../data/local/outbox/outbox_status.dart';

class Order {
  Order({
    required this.localId,
    required this.provisionalOrderNumber,
    required this.items,
    required this.createdOffline,
    this.serverId,
    this.canonicalOrderNumber,
    this.localRevision = 1,
    this.serverRevision,
    this.syncStatus = SyncStatus.localOnly,
  });

  final String localId;
  final String provisionalOrderNumber;
  final List<OrderItem> items;
  final bool createdOffline;

  String? serverId;
  String? canonicalOrderNumber;
  int localRevision;
  int? serverRevision;
  SyncStatus syncStatus;

  double get total =>
      items.fold(0, (sum, item) => sum + item.unitPrice * item.quantity);

  Map<String, Object?> toRecord() => {
        'localId': localId,
        'provisionalOrderNumber': provisionalOrderNumber,
        'items': items.map((i) => i.toRecord()).toList(),
        'createdOffline': createdOffline,
        'serverId': serverId,
        'canonicalOrderNumber': canonicalOrderNumber,
        'localRevision': localRevision,
        'serverRevision': serverRevision,
        'syncStatus': syncStatus.name,
      };

  static Order fromRecord(Map<String, Object?> record) => Order(
        localId: record['localId'] as String,
        provisionalOrderNumber: record['provisionalOrderNumber'] as String,
        items: (record['items'] as List)
            .map((e) => OrderItem.fromRecord(Map<String, Object?>.from(e as Map)))
            .toList(),
        createdOffline: record['createdOffline'] as bool,
        serverId: record['serverId'] as String?,
        canonicalOrderNumber: record['canonicalOrderNumber'] as String?,
        localRevision: record['localRevision'] as int? ?? 1,
        serverRevision: record['serverRevision'] as int?,
        syncStatus: SyncStatus.values.byName(record['syncStatus'] as String),
      );
}

class OrderItem {
  const OrderItem({
    required this.productId,
    required this.name,
    required this.unitPrice,
    required this.quantity,
    this.station = '',
  });

  final String productId;
  final String name;
  final double unitPrice;
  final int quantity;

  /// The kitchen station that prepares this line, used to route tickets.
  final String station;

  Map<String, Object?> toRecord() => {
        'productId': productId,
        'name': name,
        'unitPrice': unitPrice,
        'quantity': quantity,
        if (station.isNotEmpty) 'station': station,
      };

  static OrderItem fromRecord(Map<String, Object?> record) => OrderItem(
        productId: record['productId'] as String,
        name: record['name'] as String,
        unitPrice: (record['unitPrice'] as num).toDouble(),
        quantity: record['quantity'] as int,
        station: record['station'] as String? ?? '',
      );
}

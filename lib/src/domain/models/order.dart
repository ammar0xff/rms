import '../local/outbox/outbox_status.dart';

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
}

class OrderItem {
  const OrderItem({
    required this.productId,
    required this.name,
    required this.unitPrice,
    required this.quantity,
  });

  final String productId;
  final String name;
  final double unitPrice;
  final int quantity;
}

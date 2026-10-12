import 'order.dart';
import 'order_type.dart';

/// The caller-supplied inputs for a new order. The repository assigns identity,
/// the provisional number, and sync metadata.
class OrderDraft {
  const OrderDraft({
    required this.items,
    this.createdOffline = false,
    this.orderType = OrderType.dineIn,
  });

  final List<OrderItem> items;
  final bool createdOffline;
  final OrderType orderType;
}

import 'order.dart';
import 'order_type.dart';

/// The caller-supplied inputs for a new order. The repository assigns identity,
/// the provisional number, and sync metadata.
class OrderDraft {
  const OrderDraft({
    required this.items,
    this.createdOffline = false,
    this.orderType = OrderType.dineIn,
    this.taxAmount = 0.0,
    this.discountAmount = 0.0,
    this.serviceAmount = 0.0,
  });

  final List<OrderItem> items;
  final double taxAmount;
  final double discountAmount;
  final double serviceAmount;
  final bool createdOffline;
  final OrderType orderType;
}

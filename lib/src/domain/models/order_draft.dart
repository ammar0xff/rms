import 'order.dart';
import 'order_type.dart';

/// The caller-supplied inputs for a new order. The repository assigns identity,
/// the provisional number, and sync metadata.
class OrderDraft {
  const OrderDraft({
    required this.items,
    this.createdOffline = false,
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
  });

  final List<OrderItem> items;
  final double taxAmount;
  final double discountAmount;
  final double serviceAmount;
  final double deliveryFee;
  final bool createdOffline;
  final OrderType orderType;
  final String? customerId;
  final String? customerName;
  final String? customerPhone;
  final String? deliveryAddress;
  final double? deliveryLatitude;
  final double? deliveryLongitude;
  final String? branchId;
}

import 'order.dart';

/// The caller-supplied inputs for a new order. The repository assigns identity,
/// the provisional number, and sync metadata.
class OrderDraft {
  const OrderDraft({
    required this.items,
    this.createdOffline = false,
  });

  final List<OrderItem> items;
  final bool createdOffline;
}

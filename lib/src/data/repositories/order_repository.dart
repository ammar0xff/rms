import '../../domain/models/order.dart';
import '../../domain/models/order_draft.dart';

/// Local-first order access. Implementations must persist an order and its
/// pending sync command atomically.
abstract class OrderRepository {
  Future<Order> createOrder(OrderDraft draft);

  Future<List<Order>> listOrders();

  Stream<List<Order>> watchOrders() => Stream.fromFuture(listOrders());
}

import '../../domain/models/order.dart';
import '../../domain/models/order_draft.dart';

/// Local-first order access. Implementations must persist an order and its
/// pending sync command atomically.
abstract class OrderRepository {
  Future<Order> createOrder(OrderDraft draft);

  Future<List<Order>> listOrders({String? branchId, String? customerId});

  Future<List<Order>> getOrdersByCustomer(String customerId);

  Future<List<Order>> getOrdersByBranch(String branchId);

  Future<Order?> rerouteOrder({
    required String orderId,
    required String targetBranchId,
  });

  Stream<List<Order>> watchOrders() => Stream.fromFuture(listOrders());
}

import '../../domain/models/purchase_order.dart';

/// Result of trying to receive a purchase order.
enum PurchaseReceiveOutcome {
  /// The order was open and its lines were posted to stock.
  received,

  /// The order had already been received; nothing changed (idempotent).
  alreadyReceived,

  /// No purchase order matched the id.
  notFound,
}

/// Result of trying to cancel a purchase order.
enum PurchaseCancelOutcome {
  /// The order was open and is now cancelled.
  cancelled,

  /// The order was already received, so its lines are in stock and it cannot be
  /// cancelled.
  alreadyReceived,

  /// The order was already cancelled; nothing changed (idempotent).
  alreadyCancelled,

  /// No purchase order matched the id.
  notFound,
}

/// Local-first access to purchase orders.
abstract class PurchaseRepository {
  /// All purchase orders, oldest first.
  Future<List<PurchaseOrderModel>> listPurchases();

  /// Raises a new purchase order against a supplier.
  Future<PurchaseOrderModel> createPurchase({
    required String supplierId,
    required String supplierName,
    required String reference,
    required List<PurchaseOrderLine> lines,
    bool createdOffline = false,
  });

  /// Receives an order, posting one receipt movement per line to stock.
  ///
  /// Does nothing and reports [PurchaseReceiveOutcome.alreadyReceived] if the
  /// order was already received.
  Future<PurchaseReceiveOutcome> receivePurchase(
    String id, {
    bool createdOffline = false,
  });

  /// Cancels an order that has not been received yet.
  ///
  /// Only open orders can be cancelled: a received order has already posted its
  /// lines to stock, so it reports [PurchaseCancelOutcome.alreadyReceived] and
  /// changes nothing. Cancelling an already-cancelled order is a no-op.
  Future<PurchaseCancelOutcome> cancelPurchase(
    String id, {
    bool createdOffline = false,
  });
}

import '../local/outbox/outbox_entry.dart';
import '../../domain/models/stock_transfer.dart';

/// Local-first inter-branch stock transfers.
abstract class TransferRepository {
  /// All transfers, newest first.
  Future<List<StockTransfer>> listTransfers();

  /// Requests stock from a donor branch.
  Future<StockTransfer> requestTransfer({
    required String itemId,
    required String itemName,
    required double quantity,
    required String unit,
    required String fromBranchId,
    required String fromBranchName,
    required String toBranchId,
    required String toBranchName,
    String courier = '',
    String? note,
  });

  /// Moves requested → approved → inTransit, in that order only.
  Future<StockTransfer> advanceTransfer(String id);

  /// Cancels an open transfer. Received ones stay (audit trail).
  Future<StockTransfer> cancelTransfer(String id);

  /// Books the receipt leg as an inventory movement and closes the
  /// transfer. Idempotent — receiving twice never double-posts stock.
  Future<StockTransfer> receiveTransfer(String id);

  /// Marks the acknowledged entry synced (see OutboxStore).
  Future<void> applySynced(OutboxEntry entry);
}

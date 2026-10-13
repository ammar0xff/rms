import '../../domain/models/inventory_item.dart';
import '../../domain/models/stock_movement.dart';

/// Result of a conflict-aware physical stock count.
enum StockCountOutcome {
  /// The count matched the device's revision and was applied.
  applied,

  /// Another change landed since the caller's snapshot; the count was kept for
  /// explicit review instead of overwriting the newer balance.
  conflict,
}

/// Local-first access to stock levels and the append-only stock ledger.
abstract class InventoryRepository {
  /// All tracked items, ordered by name.
  Future<List<InventoryItemModel>> listItems();

  /// The stock ledger, oldest first, optionally filtered to a single item.
  Future<List<StockMovementModel>> listMovements({String? itemId});

  /// Appends a relative movement and updates the cached balance.
  Future<InventoryItemModel> recordMovement({
    required String itemId,
    required double delta,
    required StockMovementReason reason,
    String? reference,
    bool createdOffline = false,
  });

  /// Records a physical count, setting on-hand to [counted].
  ///
  /// A non-null [baseRevision] that no longer matches the item flags a conflict
  /// instead of applying the count.
  Future<StockCountOutcome> adjustToCount({
    required String itemId,
    required double counted,
    int? baseRevision,
    bool createdOffline = false,
  });

  /// Replaces (or upserts) cached items, e.g. after a backend read.
  Future<void> cacheItems(
    List<InventoryItemModel> items, {
    bool replace = true,
  });
}

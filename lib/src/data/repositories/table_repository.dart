import '../local/outbox/outbox_entry.dart';
import '../../domain/models/dining_table.dart';

/// Local-first dine-in floor state.
abstract class TableRepository {
  /// All tables, ordered by zone then code.
  Future<List<DiningTable>> listTables();

  /// Seats a party: vacant → occupied with steward and time.
  Future<DiningTable> seatTable({
    required String tableId,
    required int partySize,
    String steward = '',
    String? orderRef,
  });

  /// Guest asked for the bill; tab stays open until paid.
  Future<DiningTable> requestBill(String tableId);

  /// Frees the table after payment. Clears party, order, and total.
  Future<DiningTable> clearTable(String tableId);

  /// Marks the acknowledged entry synced (see OutboxStore).
  Future<void> applySynced(OutboxEntry entry);

  /// Replaces the floor definition (zones/capacity edits). Never deletes
  /// tables with an open tab — those throw instead.
  Future<void> saveFloor(List<DiningTable> tables);
}

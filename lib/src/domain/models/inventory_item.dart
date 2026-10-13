import '../../data/local/outbox/outbox_status.dart';

/// A stock-keeping unit with a cached on-hand balance.
///
/// [onHand] is maintained transactionally alongside the append-only stock
/// ledger, so the opening balance plus the sum of every movement always equals
/// the cached balance. [localRevision] advances on each local change and is
/// carried by a physical count so a stale count is detected instead of silently
/// applied.
class InventoryItemModel {
  InventoryItemModel({
    required this.id,
    required this.name,
    required this.unit,
    required this.onHand,
    required this.reorderAt,
    this.localRevision = 1,
    this.syncStatus = SyncStatus.pendingSync,
  });

  final String id;
  final String name;
  final String unit;
  double onHand;
  final double reorderAt;
  int localRevision;
  SyncStatus syncStatus;

  bool get isLow => onHand <= reorderAt;

  Map<String, Object?> toRecord() => {
        'id': id,
        'name': name,
        'unit': unit,
        'onHand': onHand,
        'reorderAt': reorderAt,
        'localRevision': localRevision,
        'syncStatus': syncStatus.name,
      };

  static InventoryItemModel fromRecord(Map<String, Object?> record) =>
      InventoryItemModel(
        id: record['id'] as String,
        name: record['name'] as String,
        unit: record['unit'] as String,
        onHand: (record['onHand'] as num).toDouble(),
        reorderAt: (record['reorderAt'] as num).toDouble(),
        localRevision: record['localRevision'] as int? ?? 1,
        syncStatus: SyncStatus.values.byName(record['syncStatus'] as String),
      );
}

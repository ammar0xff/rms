import '../../data/local/outbox/outbox_status.dart';

/// Why stock moved. Reasons only label a movement; the recorded
/// [StockMovementModel.delta] is always the source of truth for direction.
enum StockMovementReason {
  opening('رصيد افتتاحي'),
  receipt('استلام مشتريات'),
  sale('بيع'),
  delivery('توصيل'),
  spoilage('تلف'),
  adjustment('تسوية جرد'),
  transfer('تحويل بين الفروع'),
  customerReturn('مرتجع عميل');

  const StockMovementReason(this.label);

  final String label;
}

/// One append-only line in the stock ledger.
///
/// Because stock is the sum of its movements, concurrent relative movements
/// ([StockMovementReason.receipt], [StockMovementReason.sale], ...) commute and
/// never conflict. Only an absolute physical count, recorded through
/// `adjustToCount` with a [baseRevision], can conflict — and that is flagged for
/// explicit review rather than overwritten.
class StockMovementModel {
  StockMovementModel({
    required this.id,
    required this.itemId,
    required this.delta,
    required this.reason,
    required this.at,
    this.reference,
    this.baseRevision,
    this.createdOffline = false,
    this.syncStatus = SyncStatus.pendingSync,
  });

  final String id;
  final String itemId;

  /// Signed change to on-hand; negative for outbound movements.
  final double delta;
  final StockMovementReason reason;
  final DateTime at;
  final String? reference;

  /// The item revision an absolute adjustment was based on, or null for a
  /// relative movement.
  final int? baseRevision;
  final bool createdOffline;
  SyncStatus syncStatus;

  bool get isIncrease => delta > 0;

  Map<String, Object?> toRecord() => {
        'id': id,
        'itemId': itemId,
        'delta': delta,
        'reason': reason.name,
        'at': at.toIso8601String(),
        'reference': reference,
        'baseRevision': baseRevision,
        'createdOffline': createdOffline,
        'syncStatus': syncStatus.name,
      };

  static StockMovementModel fromRecord(Map<String, Object?> record) =>
      StockMovementModel(
        id: record['id'] as String,
        itemId: record['itemId'] as String,
        delta: (record['delta'] as num).toDouble(),
        reason:
            StockMovementReason.values.byName(record['reason'] as String),
        at: DateTime.parse(record['at'] as String),
        reference: record['reference'] as String?,
        baseRevision: record['baseRevision'] as int?,
        createdOffline: record['createdOffline'] as bool? ?? false,
        syncStatus: SyncStatus.values.byName(record['syncStatus'] as String),
      );
}

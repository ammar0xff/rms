import '../../data/local/outbox/outbox_status.dart';

enum PurchaseOrderStatus {
  ordered('مطلوب'),
  received('مستلم'),
  cancelled('ملغى');

  const PurchaseOrderStatus(this.label);

  final String label;
}

/// One line on a purchase order: how much of an item is being bought and at
/// what unit cost.
class PurchaseOrderLine {
  const PurchaseOrderLine({
    required this.itemId,
    required this.name,
    required this.quantity,
    required this.unitCost,
  });

  final String itemId;
  final String name;
  final double quantity;
  final double unitCost;

  double get total => quantity * unitCost;

  Map<String, Object?> toRecord() => {
        'itemId': itemId,
        'name': name,
        'quantity': quantity,
        'unitCost': unitCost,
      };

  static PurchaseOrderLine fromRecord(Map<String, Object?> record) =>
      PurchaseOrderLine(
        itemId: record['itemId'] as String,
        name: record['name'] as String,
        quantity: (record['quantity'] as num).toDouble(),
        unitCost: (record['unitCost'] as num).toDouble(),
      );
}

/// A purchase order raised against a supplier.
///
/// Receiving an order posts one [StockMovementReason.receipt] movement per line
/// through the stock ledger, so purchasing feeds inventory atomically and
/// idempotently: a retried receive can never double the stock.
class PurchaseOrderModel {
  PurchaseOrderModel({
    required this.id,
    required this.supplierId,
    required this.supplierName,
    required this.reference,
    required this.lines,
    this.status = PurchaseOrderStatus.ordered,
    required this.createdAt,
    this.receivedAt,
    this.createdOffline = false,
    this.localRevision = 1,
    this.syncStatus = SyncStatus.pendingSync,
  });

  final String id;
  final String supplierId;
  final String supplierName;
  final String reference;
  final List<PurchaseOrderLine> lines;
  PurchaseOrderStatus status;
  final DateTime createdAt;
  DateTime? receivedAt;
  final bool createdOffline;
  int localRevision;
  SyncStatus syncStatus;

  double get total => lines.fold<double>(0, (sum, line) => sum + line.total);

  bool get isReceived => status == PurchaseOrderStatus.received;

  bool get isOpen => status == PurchaseOrderStatus.ordered;

  Map<String, Object?> toRecord() => {
        'id': id,
        'supplierId': supplierId,
        'supplierName': supplierName,
        'reference': reference,
        'lines': [for (final line in lines) line.toRecord()],
        'lineCount': lines.length,
        'total': total,
        'status': status.name,
        'createdAt': createdAt.toIso8601String(),
        'receivedAt': receivedAt?.toIso8601String(),
        'createdOffline': createdOffline,
        'localRevision': localRevision,
        'syncStatus': syncStatus.name,
      };

  static PurchaseOrderModel fromRecord(Map<String, Object?> record) =>
      PurchaseOrderModel(
        id: record['id'] as String,
        supplierId: record['supplierId'] as String,
        supplierName: record['supplierName'] as String,
        reference: record['reference'] as String,
        lines: [
          for (final entry in (record['lines'] as List? ?? const []))
            PurchaseOrderLine.fromRecord(
              Map<String, Object?>.from(entry as Map),
            ),
        ],
        status: PurchaseOrderStatus.values.byName(record['status'] as String),
        createdAt: DateTime.parse(record['createdAt'] as String),
        receivedAt: record['receivedAt'] == null
            ? null
            : DateTime.parse(record['receivedAt'] as String),
        createdOffline: record['createdOffline'] as bool? ?? false,
        localRevision: record['localRevision'] as int? ?? 1,
        syncStatus: SyncStatus.values.byName(record['syncStatus'] as String),
      );
}

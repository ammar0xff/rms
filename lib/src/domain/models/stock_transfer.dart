import '../../data/local/outbox/outbox_status.dart';

/// Lifecycle of an inter-branch stock transfer.
enum TransferStatus {
  requested('مطلوبة'),
  approved('معتمدة'),
  inTransit('في الطريق'),
  received('اتستلمت'),
  cancelled('ملغية');

  const TransferStatus(this.label);

  final String label;

  bool get isOpen =>
      this == TransferStatus.requested ||
      this == TransferStatus.approved ||
      this == TransferStatus.inTransit;
}

/// One inter-branch stock movement request. The legs post as paired
/// inventory movements (transfer reason) on receive: issue on the donor is
/// booked by the donor branch, receipt here — phase 1 books the receipt
/// leg locally and the issue leg travels in the outbox payload for the
/// donor to apply.
class StockTransfer {
  StockTransfer({
    required this.id,
    required this.itemId,
    required this.itemName,
    required this.quantity,
    required this.unit,
    required this.fromBranchId,
    required this.fromBranchName,
    required this.toBranchId,
    required this.toBranchName,
    this.courier = '',
    this.note,
    this.status = TransferStatus.requested,
    required this.createdAt,
    this.decidedAt,
    this.syncStatus = SyncStatus.pendingSync,
  });

  final String id;
  final String itemId;
  final String itemName;
  final double quantity;
  final String unit;
  final String fromBranchId;
  final String fromBranchName;
  final String toBranchId;
  final String toBranchName;
  String courier;
  String? note;
  TransferStatus status;
  final DateTime createdAt;
  DateTime? decidedAt;
  SyncStatus syncStatus;

  Map<String, Object?> toRecord() => {
        'id': id,
        'itemId': itemId,
        'itemName': itemName,
        'quantity': quantity,
        'unit': unit,
        'fromBranchId': fromBranchId,
        'fromBranchName': fromBranchName,
        'toBranchId': toBranchId,
        'toBranchName': toBranchName,
        'courier': courier,
        'note': note,
        'status': status.name,
        'createdAt': createdAt.toIso8601String(),
        'decidedAt': decidedAt?.toIso8601String(),
        'syncStatus': syncStatus.name,
      };

  static StockTransfer fromRecord(Map<String, Object?> record) =>
      StockTransfer(
        id: record['id'] as String,
        itemId: record['itemId'] as String,
        itemName: record['itemName'] as String,
        quantity: (record['quantity'] as num).toDouble(),
        unit: record['unit'] as String? ?? '',
        fromBranchId: record['fromBranchId'] as String,
        fromBranchName: record['fromBranchName'] as String? ?? '',
        toBranchId: record['toBranchId'] as String,
        toBranchName: record['toBranchName'] as String? ?? '',
        courier: record['courier'] as String? ?? '',
        note: record['note'] as String?,
        status: TransferStatus.values
            .byName(record['status'] as String? ?? 'requested'),
        createdAt: DateTime.parse(record['createdAt'] as String),
        decidedAt: record['decidedAt'] == null
            ? null
            : DateTime.parse(record['decidedAt'] as String),
        syncStatus: SyncStatus.values
            .byName(record['syncStatus'] as String? ?? 'pendingSync'),
      );
}

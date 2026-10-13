import '../../data/local/outbox/outbox_status.dart';

/// A vendor the restaurant buys stock from.
///
/// [payable] is the running amount owed to the supplier, maintained alongside
/// purchase orders. Suppliers are local-first and only stamped
/// [SyncStatus.synced] once the backend acknowledges them.
class SupplierModel {
  SupplierModel({
    required this.id,
    required this.name,
    this.phone = '',
    this.category = '',
    this.payable = 0,
    this.localRevision = 1,
    this.syncStatus = SyncStatus.pendingSync,
  });

  final String id;
  final String name;
  final String phone;
  final String category;
  double payable;
  int localRevision;
  SyncStatus syncStatus;

  Map<String, Object?> toRecord() => {
        'id': id,
        'name': name,
        'phone': phone,
        'category': category,
        'payable': payable,
        'localRevision': localRevision,
        'syncStatus': syncStatus.name,
      };

  static SupplierModel fromRecord(Map<String, Object?> record) => SupplierModel(
        id: record['id'] as String,
        name: record['name'] as String,
        phone: record['phone'] as String? ?? '',
        category: record['category'] as String? ?? '',
        payable: (record['payable'] as num?)?.toDouble() ?? 0,
        localRevision: record['localRevision'] as int? ?? 1,
        syncStatus: SyncStatus.values.byName(record['syncStatus'] as String),
      );
}

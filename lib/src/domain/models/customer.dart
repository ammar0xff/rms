import '../../data/local/outbox/outbox_status.dart';

/// A customer of the restaurant: the delivery address book.
///
/// Customers are local-first and only stamped [SyncStatus.synced] once the
/// backend acknowledges them. There are no derived statistics here — order
/// counts and spend belong to orders, not to this record.
class CustomerModel {
  CustomerModel({
    required this.id,
    required this.name,
    this.phone = '',
    this.notes = '',
    DateTime? createdAt,
    this.localRevision = 1,
    this.syncStatus = SyncStatus.pendingSync,
  }) : createdAt = createdAt ?? DateTime.now();

  final String id;
  final String name;
  final String phone;
  final String notes;
  final DateTime createdAt;
  int localRevision;
  SyncStatus syncStatus;

  Map<String, Object?> toRecord() => {
        'id': id,
        'name': name,
        'phone': phone,
        'notes': notes,
        'createdAt': createdAt.toIso8601String(),
        'localRevision': localRevision,
        'syncStatus': syncStatus.name,
      };

  static CustomerModel fromRecord(Map<String, Object?> record) =>
      CustomerModel(
        id: record['id'] as String,
        name: record['name'] as String,
        phone: record['phone'] as String? ?? '',
        notes: record['notes'] as String? ?? '',
        createdAt: record['createdAt'] == null
            ? DateTime.fromMillisecondsSinceEpoch(0)
            : DateTime.parse(record['createdAt'] as String),
        localRevision: record['localRevision'] as int? ?? 1,
        syncStatus: SyncStatus.values.byName(record['syncStatus'] as String),
      );
}

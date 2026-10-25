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
    this.address = '',
    this.latitude,
    this.longitude,
    this.branchId = '',
    this.notes = '',
    this.totalOrders = 0,
    this.lastOrderAt,
    DateTime? createdAt,
    this.localRevision = 1,
    this.syncStatus = SyncStatus.pendingSync,
  }) : createdAt = createdAt ?? DateTime.now();

  final String id;
  final String name;
  final String phone;
  final String address;
  final double? latitude;
  final double? longitude;
  final String branchId;
  final String notes;
  int totalOrders;
  DateTime? lastOrderAt;
  final DateTime createdAt;
  int localRevision;
  SyncStatus syncStatus;

  Map<String, Object?> toRecord() => {
        'id': id,
        'name': name,
        'phone': phone,
        'address': address,
        'latitude': latitude,
        'longitude': longitude,
        'branchId': branchId,
        'notes': notes,
        'totalOrders': totalOrders,
        'lastOrderAt': lastOrderAt?.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'localRevision': localRevision,
        'syncStatus': syncStatus.name,
      };

  static CustomerModel fromRecord(Map<String, Object?> record) =>
      CustomerModel(
        id: record['id'] as String,
        name: record['name'] as String,
        phone: record['phone'] as String? ?? '',
        address: record['address'] as String? ?? '',
        latitude: (record['latitude'] as num?)?.toDouble(),
        longitude: (record['longitude'] as num?)?.toDouble(),
        branchId: record['branchId'] as String? ?? '',
        notes: record['notes'] as String? ?? '',
        totalOrders: (record['totalOrders'] as int?) ?? 0,
        lastOrderAt: record['lastOrderAt'] != null
            ? DateTime.tryParse(record['lastOrderAt'] as String)
            : null,
        createdAt: record['createdAt'] == null
            ? DateTime.fromMillisecondsSinceEpoch(0)
            : (DateTime.tryParse(record['createdAt'] as String) ?? DateTime.fromMillisecondsSinceEpoch(0)),
        localRevision: record['localRevision'] as int? ?? 1,
        syncStatus: () {
          final s = record['syncStatus'] as String?;
          if (s == null) return SyncStatus.pendingSync;
          try {
            return SyncStatus.values.byName(s);
          } catch (_) {
            return SyncStatus.pendingSync;
          }
        }(),
      );
}

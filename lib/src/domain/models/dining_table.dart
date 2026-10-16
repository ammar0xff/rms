import '../../data/local/outbox/outbox_status.dart';

/// Dine-in table state.
enum TableStatus {
  vacant('شاغرة'),
  occupied('مشغولة'),
  billRequested('مطلوب الشيك');

  const TableStatus(this.label);

  final String label;
}

/// One dine-in table. Operational state only — the running tab lives on
/// the linked order, never here, so seating and billing stay separate
/// concerns like delivery and collection do.
class DiningTable {
  DiningTable({
    required this.id,
    required this.code,
    this.zone = 'الصالة',
    this.capacity = 4,
    this.status = TableStatus.vacant,
    this.partySize = 0,
    this.steward = '',
    this.currentOrderRef,
    this.runningTotal = 0,
    this.seatedAt,
    this.syncStatus = SyncStatus.pendingSync,
  });

  final String id;

  /// Short floor code shown on the map (T-04).
  final String code;
  final String zone;
  final int capacity;
  TableStatus status;
  int partySize;
  String steward;
  String? currentOrderRef;
  double runningTotal;
  DateTime? seatedAt;
  SyncStatus syncStatus;

  Map<String, Object?> toRecord() => {
        'id': id,
        'code': code,
        'zone': zone,
        'capacity': capacity,
        'status': status.name,
        'partySize': partySize,
        'steward': steward,
        'currentOrderRef': currentOrderRef,
        'runningTotal': runningTotal,
        'seatedAt': seatedAt?.toIso8601String(),
        'syncStatus': syncStatus.name,
      };

  static DiningTable fromRecord(Map<String, Object?> record) => DiningTable(
        id: record['id'] as String,
        code: record['code'] as String,
        zone: record['zone'] as String? ?? 'الصالة',
        capacity: (record['capacity'] as num?)?.toInt() ?? 4,
        status: TableStatus.values.byName(
            record['status'] as String? ?? 'vacant'),
        partySize: (record['partySize'] as num?)?.toInt() ?? 0,
        steward: record['steward'] as String? ?? '',
        currentOrderRef: record['currentOrderRef'] as String?,
        runningTotal: (record['runningTotal'] as num?)?.toDouble() ?? 0,
        seatedAt: record['seatedAt'] == null
            ? null
            : DateTime.parse(record['seatedAt'] as String),
        syncStatus: SyncStatus.values
            .byName(record['syncStatus'] as String? ?? 'pendingSync'),
      );
}

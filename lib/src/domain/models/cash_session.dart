import '../../data/local/outbox/outbox_status.dart';

enum CashSessionStatus {
  open('مفتوحة'),
  closed('مغلقة');

  const CashSessionStatus(this.label);

  final String label;
}

/// A cashier drawer session: opened with a float, closed after counting.
///
/// [expectedCash] is derived from the cash movements recorded on the device
/// between [openedAt] and [closedAt]; the [variance] is what the counter found
/// versus what the ledger implies. Sessions are local-first and only stamped
/// [SyncStatus.synced] once the backend acknowledges them.
class CashSession {
  CashSession({
    required this.id,
    required this.openedAt,
    required this.openingFloat,
    this.closedAt,
    this.countedCash,
    this.expectedCash,
    this.droppedCash = 0.0,
    this.status = CashSessionStatus.open,
    this.note,
    this.cashierUid,
    this.cashierName,
    this.branchId,
    this.branchName,
    this.createdOffline = false,
    this.syncStatus = SyncStatus.pendingSync,
  });

  final String id;
  final DateTime openedAt;
  final double openingFloat;
  DateTime? closedAt;
  double? countedCash;
  double? expectedCash;
  double droppedCash;
  CashSessionStatus status;
  String? note;
  final String? cashierUid;
  final String? cashierName;
  final String? branchId;
  final String? branchName;
  final bool createdOffline;
  SyncStatus syncStatus;

  bool get isOpen => status == CashSessionStatus.open;

  double? get variance {
    final counted = countedCash;
    final expected = expectedCash;
    if (counted == null || expected == null) return null;
    return counted - expected;
  }

  Map<String, Object?> toRecord() => {
        'id': id,
        'openedAt': openedAt.toIso8601String(),
        'openingFloat': openingFloat,
        'closedAt': closedAt?.toIso8601String(),
        'countedCash': countedCash,
        'expectedCash': expectedCash,
        'droppedCash': droppedCash,
        'status': status.name,
        'note': note,
        'cashierUid': cashierUid,
        'cashierName': cashierName,
        'branchId': branchId,
        'branchName': branchName,
        'createdOffline': createdOffline,
        'syncStatus': syncStatus.name,
      };

  static CashSession fromRecord(Map<String, Object?> record) => CashSession(
        id: (record['id'] ?? '') as String,
        openedAt: record['openedAt'] != null
            ? (DateTime.tryParse(record['openedAt'].toString()) ?? DateTime.now())
            : DateTime.now(),
        openingFloat: (record['openingFloat'] as num?)?.toDouble() ?? 500.0,
        closedAt: record['closedAt'] == null
            ? null
            : DateTime.tryParse(record['closedAt'].toString()),
        countedCash: (record['countedCash'] as num?)?.toDouble(),
        expectedCash: (record['expectedCash'] as num?)?.toDouble(),
        droppedCash: (record['droppedCash'] as num?)?.toDouble() ?? 0.0,
        status: () {
          final s = record['status'] as String?;
          if (s == null) return CashSessionStatus.open;
          try {
            return CashSessionStatus.values.byName(s);
          } catch (_) {
            return CashSessionStatus.open;
          }
        }(),
        note: record['note'] as String?,
        cashierUid: record['cashierUid'] as String?,
        cashierName: record['cashierName'] as String?,
        branchId: record['branchId'] as String?,
        branchName: record['branchName'] as String?,
        createdOffline: record['createdOffline'] as bool? ?? false,
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

  CashSession copyWith({
    String? id,
    DateTime? openedAt,
    double? openingFloat,
    DateTime? closedAt,
    double? countedCash,
    double? expectedCash,
    double? droppedCash,
    CashSessionStatus? status,
    String? note,
    String? cashierUid,
    String? cashierName,
    String? branchId,
    String? branchName,
    bool? createdOffline,
    SyncStatus? syncStatus,
  }) =>
      CashSession(
        id: id ?? this.id,
        openedAt: openedAt ?? this.openedAt,
        openingFloat: openingFloat ?? this.openingFloat,
        closedAt: closedAt ?? this.closedAt,
        countedCash: countedCash ?? this.countedCash,
        expectedCash: expectedCash ?? this.expectedCash,
        droppedCash: droppedCash ?? this.droppedCash,
        status: status ?? this.status,
        note: note ?? this.note,
        cashierUid: cashierUid ?? this.cashierUid,
        cashierName: cashierName ?? this.cashierName,
        branchId: branchId ?? this.branchId,
        branchName: branchName ?? this.branchName,
        createdOffline: createdOffline ?? this.createdOffline,
        syncStatus: syncStatus ?? this.syncStatus,
      );
}

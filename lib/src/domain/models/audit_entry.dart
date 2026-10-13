/// What a recorded audit event describes.
enum AuditAction {
  openCashSession('فتح جلسة نقدية'),
  closeCashSession('إغلاق جلسة نقدية'),
  recordPayment('تسجيل دفعة'),
  recordRefund('تسجيل استرداد'),
  recordCollection('تسجيل تحصيل'),
  settleDelivery('تسوية توصيل'),
  reassignConflict('تعارض إعادة إسناد'),
  requestApproval('طلب اعتماد مالي'),
  approveRequest('اعتماد طلب مالي'),
  rejectRequest('رفض طلب مالي'),
  recordStockMovement('تسجيل حركة مخزون'),
  stockConflict('تعارض جرد مخزون'),
  schemaMigration('ترحيل المخطط المحلي');

  const AuditAction(this.label);

  final String label;
}

/// Append-only audit record.
///
/// Rows are never edited or deleted: a correction is a new event. Each row is
/// written in the same transaction as the operation it describes, so money can
/// never move without leaving a local trace.
class AuditEntry {
  const AuditEntry({
    required this.id,
    required this.action,
    required this.entityType,
    required this.entityId,
    required this.summary,
    required this.at,
    this.actor = 'system',
    this.amount,
    this.createdOffline = false,
  });

  final String id;
  final AuditAction action;
  final String entityType;
  final String entityId;
  final String summary;
  final DateTime at;
  final String actor;
  final double? amount;
  final bool createdOffline;

  Map<String, Object?> toRecord() => {
        'id': id,
        'action': action.name,
        'entityType': entityType,
        'entityId': entityId,
        'summary': summary,
        'at': at.toIso8601String(),
        'actor': actor,
        'amount': amount,
        'createdOffline': createdOffline,
      };

  static AuditEntry fromRecord(Map<String, Object?> record) => AuditEntry(
        id: record['id'] as String,
        action: AuditAction.values.byName(record['action'] as String),
        entityType: record['entityType'] as String,
        entityId: record['entityId'] as String,
        summary: record['summary'] as String,
        at: DateTime.parse(record['at'] as String),
        actor: record['actor'] as String? ?? 'system',
        amount: (record['amount'] as num?)?.toDouble(),
        createdOffline: record['createdOffline'] as bool? ?? false,
      );
}

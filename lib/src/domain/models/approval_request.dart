import '../../data/local/outbox/outbox_status.dart';
import 'payment.dart';

enum ApprovalKind {
  refund('استرداد'),
  adjustment('تسوية يدوية');

  const ApprovalKind(this.label);

  final String label;
}

enum ApprovalStatus {
  pending('بانتظار الاعتماد'),
  approved('معتمد'),
  rejected('مرفوض');

  const ApprovalStatus(this.label);

  final String label;
}

/// A financial action that needs a second party's approval before it is posted.
///
/// Refunds are never applied at request time: the request is queued, and only an
/// explicit decision writes the correcting payment. That is what keeps an
/// offline device from silently issuing refunds.
class ApprovalRequest {
  ApprovalRequest({
    required this.id,
    required this.kind,
    required this.orderLocalId,
    required this.orderRef,
    required this.amount,
    required this.reason,
    required this.requestedAt,
    this.method = PaymentMethod.cash,
    this.requestedBy = 'cashier',
    this.status = ApprovalStatus.pending,
    this.decidedBy,
    this.decidedAt,
    this.createdOffline = false,
    this.syncStatus = SyncStatus.pendingSync,
  });

  final String id;
  final ApprovalKind kind;
  final String orderLocalId;
  final String orderRef;

  /// Positive magnitude of the amount under review.
  final double amount;
  final String reason;
  final DateTime requestedAt;
  final PaymentMethod method;
  final String requestedBy;
  ApprovalStatus status;
  String? decidedBy;
  DateTime? decidedAt;
  final bool createdOffline;
  SyncStatus syncStatus;

  bool get isPending => status == ApprovalStatus.pending;

  Map<String, Object?> toRecord() => {
        'id': id,
        'kind': kind.name,
        'orderLocalId': orderLocalId,
        'orderRef': orderRef,
        'amount': amount,
        'reason': reason,
        'requestedAt': requestedAt.toIso8601String(),
        'method': method.name,
        'requestedBy': requestedBy,
        'status': status.name,
        'decidedBy': decidedBy,
        'decidedAt': decidedAt?.toIso8601String(),
        'createdOffline': createdOffline,
        'syncStatus': syncStatus.name,
      };

  static ApprovalRequest fromRecord(Map<String, Object?> record) =>
      ApprovalRequest(
        id: record['id'] as String,
        kind: ApprovalKind.values.byName(record['kind'] as String),
        orderLocalId: record['orderLocalId'] as String,
        orderRef: record['orderRef'] as String,
        amount: (record['amount'] as num).toDouble(),
        reason: record['reason'] as String,
        requestedAt: DateTime.parse(record['requestedAt'] as String),
        method: PaymentMethod.values.byName(record['method'] as String),
        requestedBy: record['requestedBy'] as String? ?? 'cashier',
        status: ApprovalStatus.values.byName(record['status'] as String),
        decidedBy: record['decidedBy'] as String?,
        decidedAt: record['decidedAt'] == null
            ? null
            : DateTime.parse(record['decidedAt'] as String),
        createdOffline: record['createdOffline'] as bool? ?? false,
        syncStatus: SyncStatus.values.byName(record['syncStatus'] as String),
      );
}

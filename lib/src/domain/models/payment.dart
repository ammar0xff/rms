import '../../data/local/outbox/outbox_status.dart';

/// How a payment was collected.
enum PaymentMethod {
  cash('كاش'),
  card('فيزا');

  const PaymentMethod(this.label);

  final String label;
}

/// An append-only payment record.
///
/// Payments are never edited or deleted — corrections are new negative entries
/// (refunds) — so replaying a batch can only ever add rows, never mutate them.
class PaymentModel {
  PaymentModel({
    required this.id,
    required this.orderLocalId,
    required this.orderRef,
    required this.amount,
    required this.method,
    required this.createdAt,
    this.tendered,
    this.createdOffline = false,
    this.syncStatus = SyncStatus.pendingSync,
  });

  final String id;
  final String orderLocalId;
  final String orderRef;
  final double amount;
  final PaymentMethod method;
  final DateTime createdAt;

  /// Cash handed over by the customer, when known. Used to derive change.
  final double? tendered;
  final bool createdOffline;
  SyncStatus syncStatus;

  bool get isRefund => amount < 0;

  double? get changeDue {
    final given = tendered;
    if (given == null) return null;
    final change = given - amount;
    return change < 0 ? 0 : change;
  }

  Map<String, Object?> toRecord() => {
        'id': id,
        'orderLocalId': orderLocalId,
        'orderRef': orderRef,
        'amount': amount,
        'method': method.name,
        'createdAt': createdAt.toIso8601String(),
        'tendered': tendered,
        'createdOffline': createdOffline,
        'syncStatus': syncStatus.name,
      };

  static PaymentModel fromRecord(Map<String, Object?> record) => PaymentModel(
        id: record['id'] as String,
        orderLocalId: record['orderLocalId'] as String,
        orderRef: record['orderRef'] as String,
        amount: (record['amount'] as num).toDouble(),
        method: PaymentMethod.values.byName(record['method'] as String),
        createdAt: DateTime.parse(record['createdAt'] as String),
        tendered: (record['tendered'] as num?)?.toDouble(),
        createdOffline: record['createdOffline'] as bool? ?? false,
        syncStatus: SyncStatus.values.byName(record['syncStatus'] as String),
      );
}

/// Caller-supplied inputs for recording a payment.
class PaymentDraft {
  const PaymentDraft({
    required this.orderLocalId,
    required this.orderRef,
    required this.amount,
    required this.method,
    this.tendered,
    this.createdOffline = false,
  });

  final String orderLocalId;
  final String orderRef;
  final double amount;
  final PaymentMethod method;
  final double? tendered;
  final bool createdOffline;
}

import '../../domain/models/approval_request.dart';
import '../../domain/models/payment.dart';

/// Approval workflow for financial corrections that must not be posted silently.
abstract class ApprovalRepository {
  /// Queues a refund request. No money moves until it is approved.
  Future<ApprovalRequest> requestRefund({
    required String orderLocalId,
    required String orderRef,
    required double amount,
    required String reason,
    PaymentMethod method = PaymentMethod.cash,
    String requestedBy = 'cashier',
    bool createdOffline = false,
  });

  /// Queues an invoice-void request. Nothing is voided until approved.
  Future<ApprovalRequest> requestVoid({
    required String orderLocalId,
    required String orderRef,
    required double amount,
    required String reason,
    String requestedBy = 'cashier',
    bool createdOffline = false,
  });

  Future<List<ApprovalRequest>> listRequests();

  /// Approves or rejects a pending request. Approving a refund posts the
  /// correcting payment; the call is idempotent (a decided request is returned
  /// unchanged).
  Future<ApprovalRequest?> decide(
    String id, {
    required bool approved,
    String decidedBy = 'manager',
    String? note,
  });
}

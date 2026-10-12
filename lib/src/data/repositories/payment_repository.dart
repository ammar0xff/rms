import '../../domain/models/payment.dart';

/// Append-only local access to payment records.
abstract class PaymentRepository {
  /// Persists a payment and its sync command atomically.
  Future<PaymentModel> recordPayment(PaymentDraft draft);

  Future<List<PaymentModel>> listPayments();
}

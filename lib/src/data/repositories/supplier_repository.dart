import '../../domain/models/supplier.dart';

/// Result of trying to record a supplier payment.
enum SupplierPaymentOutcome {
  /// The payment was applied to the supplier's outstanding payable.
  recorded,

  /// No supplier matched the id.
  notFound,

  /// The amount was not a positive, finite number.
  invalidAmount,

  /// The amount was larger than the outstanding payable.
  exceedsPayable,
}

/// Local-first access to the supplier directory.
abstract class SupplierRepository {
  /// All suppliers, ordered by name.
  Future<List<SupplierModel>> listSuppliers();

  /// Creates and persists a supplier, queueing its sync command.
  Future<SupplierModel> createSupplier({
    required String name,
    String phone = '',
    String category = '',
    double payable = 0,
    bool createdOffline = false,
  });

  /// Records a payment against a supplier, reducing its outstanding payable.
  ///
  /// The payable is the running amount owed, so receiving a purchase order
  /// increases it and a payment decreases it. Payments never overpay: an amount
  /// above the outstanding payable reports
  /// [SupplierPaymentOutcome.exceedsPayable] and changes nothing.
  Future<SupplierPaymentOutcome> recordSupplierPayment({
    required String supplierId,
    required double amount,
    required String reference,
    bool createdOffline = false,
  });
}

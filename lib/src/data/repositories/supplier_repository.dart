import '../../domain/models/supplier.dart';

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
}

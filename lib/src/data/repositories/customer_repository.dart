import '../../domain/models/customer.dart';
import '../local/outbox/outbox_entry.dart';

abstract class CustomerRepository {
  Future<List<CustomerModel>> listCustomers();

  Future<CustomerModel> createCustomer({
    required String name,
    String phone,
    String notes,
    bool createdOffline,
  });

  /// Folds a sync acknowledgement back into the customer.
  Future<void> applySynced(OutboxEntry entry);
}

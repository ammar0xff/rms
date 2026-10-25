import '../../domain/models/customer.dart';
import '../local/outbox/outbox_entry.dart';

abstract class CustomerRepository {
  Future<List<CustomerModel>> listCustomers({String? branchId});

  Future<CustomerModel?> findByPhone(String phone);

  Future<List<CustomerModel>> searchCustomers(String query, {String? branchId});

  Future<CustomerModel> createCustomer({
    required String name,
    String phone = '',
    String address = '',
    double? latitude,
    double? longitude,
    String branchId = '',
    String notes = '',
    bool createdOffline = false,
  });

  Future<CustomerModel> saveOrUpdateCustomer({
    required String name,
    required String phone,
    String? address,
    double? latitude,
    double? longitude,
    String? branchId,
    String? notes,
    bool createdOffline = false,
  });

  Future<void> recordCustomerOrder(String customerId, {DateTime? orderAt});

  Future<void> updateCustomer(CustomerModel customer);

  /// Folds a sync acknowledgement back into the customer.
  Future<void> applySynced(OutboxEntry entry);
}

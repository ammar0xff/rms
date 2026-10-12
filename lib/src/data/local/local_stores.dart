import 'package:sembast/sembast.dart';

/// Named collections within the local database.
abstract final class LocalStores {
  static final StoreRef<String, Map<String, Object?>> orders =
      stringMapStoreFactory.store('orders');

  static final StoreRef<String, Map<String, Object?>> outbox =
      stringMapStoreFactory.store('outbox');

  static final StoreRef<String, Map<String, Object?>> menu =
      stringMapStoreFactory.store('menu');

  static final StoreRef<String, Map<String, Object?>> kitchenTickets =
      stringMapStoreFactory.store('kitchen_tickets');

  static final StoreRef<String, Map<String, Object?>> payments =
      stringMapStoreFactory.store('payments');

  static final StoreRef<String, Map<String, Object?>> deliveries =
      stringMapStoreFactory.store('deliveries');

  static final StoreRef<String, Map<String, Object?>> drivers =
      stringMapStoreFactory.store('drivers');
}

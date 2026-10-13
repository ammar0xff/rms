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

  static final StoreRef<String, Map<String, Object?>> collections =
      stringMapStoreFactory.store('collections');

  /// Per-device metadata such as the applied local schema version.
  static final StoreRef<String, Map<String, Object?>> meta =
      stringMapStoreFactory.store('meta');

  /// Append-only audit trail of local financial operations.
  static final StoreRef<String, Map<String, Object?>> audit =
      stringMapStoreFactory.store('audit');

  static final StoreRef<String, Map<String, Object?>> cashSessions =
      stringMapStoreFactory.store('cash_sessions');

  static final StoreRef<String, Map<String, Object?>> approvals =
      stringMapStoreFactory.store('approvals');

  /// Cached server configuration (release manifest / feature flags).
  static final StoreRef<String, Map<String, Object?>> config =
      stringMapStoreFactory.store('config');
}

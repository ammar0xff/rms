import 'package:sembast/sembast.dart';

/// Named collections within the local database.
abstract final class LocalStores {
  static final StoreRef<String, Map<String, Object?>> orders =
      stringMapStoreFactory.store('orders');

  static final StoreRef<String, Map<String, Object?>> customers =
      stringMapStoreFactory.store('customers');

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

  /// Stock-keeping units with their cached on-hand balance.
  static final StoreRef<String, Map<String, Object?>> inventory =
      stringMapStoreFactory.store('inventory');

  /// Append-only stock ledger (the source of truth for on-hand).
  static final StoreRef<String, Map<String, Object?>> stockMovements =
      stringMapStoreFactory.store('stock_movements');

  /// Vendors stock is purchased from.
  static final StoreRef<String, Map<String, Object?>> suppliers =
      stringMapStoreFactory.store('suppliers');

  /// Purchase orders raised against suppliers.
  static final StoreRef<String, Map<String, Object?>> purchases =
      stringMapStoreFactory.store('purchases');

  /// Branch directory for the multi-branch network (synced directory).
  static final StoreRef<String, Map<String, Object?>> branches =
      stringMapStoreFactory.store('branches');

  /// Cached per-branch rollups used to consolidate while offline.
  static final StoreRef<String, Map<String, Object?>> branchAggregates =
      stringMapStoreFactory.store('branch_aggregates');

  /// Append-only audit trail of the update lifecycle (install, migrate,
  /// health-check, acknowledgement and rollback outcomes).
  static final StoreRef<String, Map<String, Object?>> releaseAuditEvents =
      stringMapStoreFactory.store('release_audit_events');
}

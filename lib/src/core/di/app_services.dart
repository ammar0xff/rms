import 'package:flutter/widgets.dart';

import '../config/firebase_config.dart';
import '../../data/local/audit_log.dart';
import '../../data/local/local_database.dart';
import '../../data/local/migrations/local_migration_runner.dart';
import '../../data/local/outbox/outbox_store.dart';
import '../../data/repositories/approval_repository.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/branch_repository.dart';
import '../../data/repositories/cash_session_repository.dart';
import '../../data/repositories/delivery_repository.dart';
import '../../data/repositories/feature_flag_repository.dart';
import '../../data/repositories/inventory_repository.dart';
import '../../data/repositories/kitchen_repository.dart';
import '../../data/repositories/menu_repository.dart';
import '../../data/repositories/order_repository.dart';
import '../../data/repositories/payment_repository.dart';
import '../../data/repositories/purchase_repository.dart';
import '../../data/repositories/reports_repository.dart';
import '../../data/repositories/supplier_repository.dart';
import '../../data/repositories/update_repository.dart';
import '../../data/sync/sync_service.dart';
import '../../data/services/print_service.dart';

/// Process-wide dependencies resolved once at startup.
class AppServices {
  const AppServices({
    required this.config,
    required this.auth,
    required this.firebaseReady,
    this.database,
    this.orders,
    this.menu,
    this.kitchen,
    this.payments,
    this.deliveries,
    this.outbox,
    this.sync,
    this.print,
    this.audit,
    this.cashSessions,
    this.approvals,
    this.features,
    this.migration,
    this.inventory,
    this.suppliers,
    this.purchases,
    this.reports,
    this.branches,
    this.updates,
  });

  final FirebaseConfig config;
  final AuthRepository auth;

  /// Whether Firebase initialized successfully this session.
  final bool firebaseReady;

  /// The on-device store, or null when it could not be opened.
  final LocalDatabase? database;

  /// Local-first order access, or null when the store is unavailable.
  final OrderRepository? orders;

  /// Menu cache repository (offline-first read), or null when store unavailable.
  final MenuRepository? menu;

  /// Kitchen queue (KDS) repository, or null when store unavailable.
  final KitchenRepository? kitchen;

  /// Append-only payment log, or null when store unavailable.
  final PaymentRepository? payments;

  /// Delivery jobs and courier roster, or null when store unavailable.
  final DeliveryRepository? deliveries;

  /// The transactional outbox, exposed for diagnostics and conflict resolution.
  final OutboxStore? outbox;

  /// Connectivity-driven sync loop, or null when there is no backend/store.
  final SyncService? sync;

  /// Local print service (stub).
  final PrintService? print;

  /// Append-only local audit trail, or null when the store is unavailable.
  final AuditLog? audit;

  /// Cashier drawer sessions, or null when the store is unavailable.
  final CashSessionRepository? cashSessions;

  /// Refund / correction approval workflow, or null when unavailable.
  final ApprovalRepository? approvals;

  /// Cached server release manifest and feature flags.
  final FeatureFlagRepository? features;

  /// Result of the last local schema migration attempt, or null when no store.
  final MigrationOutcome? migration;

  /// Stock items and the append-only stock ledger, or null when unavailable.
  final InventoryRepository? inventory;

  /// Supplier directory, or null when the store is unavailable.
  final SupplierRepository? suppliers;

  /// Purchase orders, or null when the store is unavailable.
  final PurchaseRepository? purchases;

  /// Local-first reporting read-model, or null when the store is unavailable.
  final ReportsRepository? reports;

  /// Branch directory and consolidation read-model, or null when unavailable.
  final BranchRepository? branches;

  /// Cached release manifest used to classify app updates, or null when
  /// unavailable.
  final UpdateRepository? updates;

  /// True when running without a backend (demo data, local sessions).
  bool get isDemo => !config.isConfigured || !firebaseReady;

  /// True when local persistence is available this session.
  bool get hasLocalStore => database != null;
}

/// Exposes [AppServices] to the widget tree.
class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.services, required super.child});

  final AppServices services;

  static AppServices of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope not found in the widget tree.');
    return scope!.services;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      oldWidget.services != services;
}

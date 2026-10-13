import 'package:flutter/widgets.dart';

import '../config/firebase_config.dart';
import '../../data/local/audit_log.dart';
import '../../data/local/local_database.dart';
import '../../data/local/migrations/local_migration_runner.dart';
import '../../data/local/outbox/outbox_store.dart';
import '../../data/repositories/approval_repository.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/cash_session_repository.dart';
import '../../data/repositories/delivery_repository.dart';
import '../../data/repositories/feature_flag_repository.dart';
import '../../data/repositories/kitchen_repository.dart';
import '../../data/repositories/menu_repository.dart';
import '../../data/repositories/order_repository.dart';
import '../../data/repositories/payment_repository.dart';
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

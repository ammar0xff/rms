import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

import '../config/app_version.dart';
import '../config/app_version_reader.dart';
import '../config/device_update_context.dart';
import '../config/firebase_config.dart';
import '../di/app_services.dart';
import '../logging/app_logger.dart';
import '../../data/local/audit_log.dart';
import '../../data/local/local_database.dart';
import '../../data/local/migrations/local_migration_registry.dart';
import '../../data/local/migrations/local_migration_runner.dart';
import '../../data/local/outbox/outbox_status.dart';
import '../../data/local/outbox/outbox_store.dart';
import '../../data/local/release_audit_log.dart';
import '../../data/local/update_acknowledgement_store.dart';
import '../../data/local/update_status_store.dart';
import '../../domain/models/update_manifest.dart';
import '../../data/updates/android_update_installer.dart';
import '../../data/updates/artifact_downloader.dart';
import '../../data/updates/firestore_update_source.dart';
import '../../data/updates/local_health_checker.dart';
import '../../data/updates/local_schema_migrator.dart';
import '../../data/updates/update_runtime.dart';
import '../../data/updates/update_service.dart';
import '../../data/repositories/demo_auth_repository.dart';
import '../../data/repositories/firebase_auth_repository.dart';
import '../../data/repositories/local_approval_repository.dart';
import '../../data/repositories/local_branch_repository.dart';
import '../../data/repositories/local_cash_session_repository.dart';
import '../../data/repositories/local_delivery_repository.dart';
import '../../data/repositories/local_feature_flag_repository.dart';
import '../../data/repositories/local_inventory_repository.dart';
import '../../data/repositories/local_kitchen_repository.dart';
import '../../data/repositories/local_menu_repository.dart';
import '../../data/repositories/local_order_repository.dart';
import '../../data/repositories/local_payment_repository.dart';
import '../../data/repositories/local_purchase_repository.dart';
import '../../data/repositories/local_reports_repository.dart';
import '../../data/repositories/local_supplier_repository.dart';
import '../../data/repositories/local_update_repository.dart';
import '../../domain/models/approval_request.dart';
import '../../domain/models/branch.dart';
import '../../domain/models/cash_session.dart';
import '../../domain/models/collection.dart';
import '../../domain/models/delivery.dart';
import '../../domain/models/inventory_item.dart';
import '../../domain/models/kitchen_ticket.dart';
import '../../domain/models/menu_item.dart';
import '../../domain/models/payment.dart';
import '../../domain/models/purchase_order.dart';
import '../../domain/models/release_manifest.dart';
import '../../domain/models/stock_movement.dart';
import '../../domain/models/supplier.dart';
import '../../data/mock/mock_data.dart' as mock;
import '../../data/sync/connectivity_monitor.dart';
import '../../data/sync/firestore_sync_transport.dart';
import '../../data/sync/sync_coordinator.dart';
import '../../data/sync/sync_engine.dart';
import '../../data/sync/sync_service.dart';
import '../../data/services/print_service.dart';
import '../state/sync_monitor.dart';

/// Resolves the app's dependencies. When Firebase is configured and reachable
/// the backend repositories are used; otherwise the app degrades to a fully
/// functional local demo so builds and the live site keep working.
///
/// The on-device store is opened independently of Firebase: if it cannot be
/// opened, the app still boots (persistence is simply disabled for the session).
Future<AppServices> bootstrapApp() async {
  final config = FirebaseConfig.fromEnvironment();
  final database = await _openLocalDatabase();
  final migration = await _runMigrations(database);

  // Before anything reads the version, so the update engine compares the
  // manifest against what is genuinely installed rather than against whatever
  // constant was compiled in.
  await AppVersionReader.hydrate();

  return _resolveAuth(config, database, migration);
}

/// Brings the on-device schema up to the version the build expects.
///
/// A failure is logged but never blocks startup: the app keeps running on the
/// last good schema rather than losing access to pending offline work.
Future<MigrationOutcome?> _runMigrations(LocalDatabase? database) async {
  if (database == null) return null;
  try {
    final outcome = await LocalMigrationRunner(
      database,
      defaultLocalMigrations,
    ).run(targetVersion: AppVersion.localSchemaVersion);
    final applied =
        outcome.applied.isEmpty ? 'none' : outcome.applied.join(', ');
    AppLogger.info(
      'Local schema v${outcome.fromVersion}→v${outcome.toVersion} (applied: $applied).',
    );
    return outcome;
  } catch (error, stackTrace) {
    AppLogger.error('Local schema migration failed.', error, stackTrace);
    return null;
  }
}

Future<AppServices> _resolveAuth(
  FirebaseConfig config,
  LocalDatabase? database,
  MigrationOutcome? migration,
) async {
  final outbox = database == null ? null : OutboxStore(database);
  final audit = database == null ? null : AuditLog(database);
  final orders = (database == null || outbox == null)
      ? null
      : LocalOrderRepository(database, outbox: outbox);
  final menu = database == null ? null : LocalMenuRepository(database);
  final kitchen = database == null ? null : LocalKitchenRepository(database);
  final payments = (database == null || outbox == null)
      ? null
      : LocalPaymentRepository(database, outbox: outbox, audit: audit);
  final deliveries = (database == null || outbox == null)
      ? null
      : LocalDeliveryRepository(database, outbox: outbox, audit: audit);
  final cashSessions = (database == null || outbox == null)
      ? null
      : LocalCashSessionRepository(database, outbox: outbox, audit: audit);
  final approvals = (database == null || outbox == null)
      ? null
      : LocalApprovalRepository(database, outbox: outbox, audit: audit);
  final features =
      database == null ? null : LocalFeatureFlagRepository(database);
  final updates = database == null ? null : LocalUpdateRepository(database);
  final updateAudit = database == null ? null : ReleaseAuditLog(database);
  final updateStatus =
      database == null ? null : LocalUpdateStatusStore(database);
  final updateAcknowledgement =
      database == null ? null : LocalUpdateAcknowledgementStore(database);

  // The update flow's collaborators. The concrete downloader is
  // platform-specific, so the factory resolves it; the runtime below assembles
  // the rest into a fresh service per check, so the readiness gate always
  // judges the local-work backlog as it is at that moment.
  final updateDownloader = createArtifactDownloader();
  final updateInstaller = AndroidUpdateInstaller();
  final updateMigrator =
      database == null ? null : LocalSchemaMigrator(database: database);
  final updateHealthCheck = database == null
      ? null
      : LocalHealthChecker(
          database: database,
          expectedSchemaVersion: AppVersion.localSchemaVersion,
        );
  final inventory = (database == null || outbox == null)
      ? null
      : LocalInventoryRepository(database, outbox: outbox, audit: audit);
  final suppliers = (database == null || outbox == null)
      ? null
      : LocalSupplierRepository(database, outbox: outbox, audit: audit);
  final purchases = (database == null || outbox == null || inventory == null)
      ? null
      : LocalPurchaseRepository(
          database,
          inventory: inventory,
          outbox: outbox,
          audit: audit,
        );
  final reports = (orders == null ||
          payments == null ||
          deliveries == null ||
          cashSessions == null ||
          inventory == null ||
          purchases == null ||
          suppliers == null)
      ? null
      : LocalReportsRepository(
          orders,
          payments,
          deliveries,
          cashSessions,
          inventory,
          purchases,
          suppliers,
          audit: audit,
          outbox: outbox,
        );
  final branches = (database == null || reports == null)
      ? null
      : LocalBranchRepository(database, reports: reports);
  await _primeMenuCache(menu);
  await _primeKitchenCache(kitchen);
  await _primeDeliveryData(deliveries);
  await _primePaymentData(payments);
  await _primeCashData(cashSessions);
  await _primeApprovalData(approvals);
  await _primeFeatureFlags(features);
  await _primeInventoryData(inventory);
  await _primePurchasingData(suppliers, purchases);
  await _primeBranchData(branches);
  await _primeUpdateManifest(updates);

  // Built here rather than alongside the other repositories: it needs
  // `branches` for the rollout cohort seed, and the Firebase instance — which
  // only exists after initializeApp — for the remote manifest source.
  // Constructed per return path below: evaluating FirebaseFirestore.instance
  // before initializeApp throws core/no-app and kills startup outside any
  // try/catch, so it must never happen eagerly up here.
  UpdateRuntime? buildRuntime({FirebaseFirestore? firestoreDb}) {
    if (database == null || updates == null) return null;
    return UpdateRuntime(
      cache: updates,
      outbox: outbox,
      acknowledgement: updateAcknowledgement,
      remote: FirestoreUpdateSource(
        platform: currentUpdatePlatform(),
        firestore: firestoreDb,
      ),
      // Web ships through its hosting provider and takes no artifact.
      artifactDeliverySupported: currentUpdatePlatform() != UpdatePlatform.web,
      online: () => SyncMonitor.instance.online,
      branchId: () async => (await branches?.activeBranch())?.id ?? '',
      buildService: () => UpdateDeps(
        downloader: updateDownloader,
        installer: updateInstaller,
        migrator: updateMigrator!,
        healthChecker: updateHealthCheck!,
        auditSink: updateAudit,
        statusStore: updateStatus,
      ),
    );
  }

  // Surface local outbox state even without a backend (demo mode); the
  // Firebase branch below re-attaches with the sync loop.
  try {
    SyncMonitor.instance.attach(outbox: outbox);
  } catch (_) {}

  if (!config.isConfigured) {
    AppLogger.warn(
      'Firebase config not provided (dart-defines missing) — running in demo mode.',
    );
    return AppServices(
      config: config,
      auth: DemoAuthRepository(),
      firebaseReady: false,
      database: database,
      orders: orders,
      menu: menu,
      kitchen: kitchen,
      payments: payments,
      deliveries: deliveries,
      outbox: outbox,
      print: PrintService(),
      audit: audit,
      cashSessions: cashSessions,
      approvals: approvals,
      features: features,
      migration: migration,
      inventory: inventory,
      suppliers: suppliers,
      purchases: purchases,
      reports: reports,
      branches: branches,
      updates: updates,
      updateAudit: updateAudit,
      updateStatus: updateStatus,
      updateAcknowledgement: updateAcknowledgement,
      updateRuntime: buildRuntime(),
    );
  }

  try {
    await Firebase.initializeApp(options: config.toOptions());
    AppLogger.info('Firebase initialized (env=${config.environment}).');
    final sync = _buildSync(outbox, orders, payments, deliveries, cashSessions,
        approvals, kitchen, inventory, suppliers, purchases);
    if (sync != null) unawaited(sync.start());
    try {
      SyncMonitor.instance.attach(sync: sync, outbox: outbox);
    } catch (_) {}
    return AppServices(
      config: config,
      auth: FirebaseAuthRepository(),
      firebaseReady: true,
      database: database,
      orders: orders,
      sync: sync,
      menu: menu,
      kitchen: kitchen,
      payments: payments,
      deliveries: deliveries,
      outbox: outbox,
      print: PrintService(),
      audit: audit,
      cashSessions: cashSessions,
      approvals: approvals,
      features: features,
      migration: migration,
      inventory: inventory,
      suppliers: suppliers,
      purchases: purchases,
      reports: reports,
      branches: branches,
      updates: updates,
      updateAudit: updateAudit,
      updateStatus: updateStatus,
      updateAcknowledgement: updateAcknowledgement,
      updateRuntime: buildRuntime(firestoreDb: FirebaseFirestore.instance),
    );
  } catch (error, stackTrace) {
    AppLogger.error(
      'Firebase initialization failed — falling back to demo mode.',
      error,
      stackTrace,
    );
    return AppServices(
      config: config,
      auth: DemoAuthRepository(),
      firebaseReady: false,
      database: database,
      orders: orders,
      menu: menu,
      kitchen: kitchen,
      payments: payments,
      deliveries: deliveries,
      outbox: outbox,
      print: PrintService(),
      audit: audit,
      cashSessions: cashSessions,
      approvals: approvals,
      features: features,
      migration: migration,
      inventory: inventory,
      suppliers: suppliers,
      purchases: purchases,
      reports: reports,
      branches: branches,
      updates: updates,
      updateAudit: updateAudit,
      updateStatus: updateStatus,
      updateAcknowledgement: updateAcknowledgement,
      updateRuntime: buildRuntime(),
    );
  }
}

/// Builds the connectivity-driven sync loop, or null when either the store or
/// the backend half is unavailable.
SyncService? _buildSync(
  OutboxStore? outbox,
  LocalOrderRepository? orders,
  LocalPaymentRepository? payments,
  LocalDeliveryRepository? deliveries,
  LocalCashSessionRepository? cashSessions,
  LocalApprovalRepository? approvals,
  LocalKitchenRepository? kitchen,
  LocalInventoryRepository? inventory,
  LocalSupplierRepository? suppliers,
  LocalPurchaseRepository? purchases,
) {
  if (outbox == null || orders == null) return null;
  final engine = SyncEngine(
    transport: FirestoreSyncTransport(),
    outbox: outbox,
    onApplied: (entry) async {
      await kitchen?.applySynced(entry);
      await orders.applySynced(entry);
      await payments?.applySynced(entry);
      await deliveries?.applySynced(entry);
      await cashSessions?.applySynced(entry);
      await approvals?.applySynced(entry);
      await inventory?.applySynced(entry);
      await suppliers?.applySynced(entry);
      await purchases?.applySynced(entry);
    },
  );
  return SyncService(
    coordinator: SyncCoordinator(engine: engine),
    connectivity: ConnectivityMonitor(),
    onSynced: (_) {
      try {
        SyncMonitor.instance.refresh();
      } catch (_) {}
    },
  );
}

/// Opens the platform store, degrading to an in-memory store (then to none) so a
/// storage failure never blocks app startup.
Future<LocalDatabase?> _openLocalDatabase() async {
  try {
    final db = await LocalDatabase.openPlatform();
    AppLogger.info('Local store ready.');
    return db;
  } catch (error, stackTrace) {
    AppLogger.error('Local store unavailable; using in-memory store.', error, stackTrace);
    try {
      return await LocalDatabase.memory();
    } catch (memoryError) {
      AppLogger.error('In-memory store unavailable; persistence disabled.', memoryError);
      return null;
    }
  }
}

Future<void> _primeMenuCache(LocalMenuRepository? menu) async {
  if (menu == null) return;
  try {
    final cached = await menu.listMenu();
    if (cached.isNotEmpty) return;
    await menu.cacheMenu(
      mock.MockData.menu.map((m) {
        return MenuItemModel(
          id: m.name,
          name: m.name,
          category: m.category,
          price: m.price,
          station: m.station,
          available: m.available,
        );
      }).toList(),
    );
  } catch (error, stackTrace) {
    AppLogger.error('Failed to prime menu cache', error, stackTrace);
  }
}

Future<void> _primeKitchenCache(LocalKitchenRepository? kitchen) async {
  if (kitchen == null) return;
  try {
    final cached = await kitchen.listTickets();
    if (cached.isNotEmpty) return;
    final now = DateTime.now();
    await kitchen.cacheTickets(
      mock.MockData.tickets.map((t) {
        return KitchenTicketModel(
          id: t.id,
          orderRef: t.orderRef,
          station: t.station,
          items: List<String>.from(t.items),
          state: switch (t.state) {
            mock.TicketState.queued => TicketState.queued,
            mock.TicketState.preparing => TicketState.preparing,
            mock.TicketState.ready => TicketState.ready,
          },
          createdAt: now.subtract(Duration(minutes: t.ageMinutes)),
          queuedAt: now.subtract(Duration(minutes: t.ageMinutes)),
          provisional: t.provisional,
        );
      }).toList(),
    );
  } catch (error, stackTrace) {
    AppLogger.error('Failed to prime kitchen cache', error, stackTrace);
  }
}

/// Seeds the courier roster and a few demo delivery jobs when the store is
/// empty, so the delivery board has something to act on in demo mode.
Future<void> _primeDeliveryData(LocalDeliveryRepository? deliveries) async {
  if (deliveries == null) return;
  try {
    final drivers = await deliveries.listDrivers();
    if (drivers.isEmpty) {
      await deliveries.cacheDrivers(const [
        DriverModel(id: 'd1', name: 'مروان ر.'),
        DriverModel(id: 'd2', name: 'سارة ك.'),
        DriverModel(id: 'd3', name: 'ديڤ ب.'),
      ]);
    }
    final cached = await deliveries.listDeliveries();
    if (cached.isNotEmpty) return;
    final now = DateTime.now();
    await deliveries.seedDeliveries([
      DeliveryModel(
        id: 'DL-0093',
        orderRef: 'ORD-4820',
        address: '42 شارع الأرز، شقة 3ب',
        amount: 27.50,
        state: DeliveryState.onRoute,
        driver: 'مروان ر.',
        createdAt: now.subtract(const Duration(minutes: 24)),
        syncStatus: SyncStatus.synced,
      ),
      DeliveryModel(
        id: 'DL-0094',
        orderRef: 'ORD-4822',
        address: '11 طريق البتولا',
        amount: 34.00,
        state: DeliveryState.assigned,
        driver: 'سارة ك.',
        offline: true,
        createdAt: now.subtract(const Duration(minutes: 18)),
        syncStatus: SyncStatus.synced,
      ),
      DeliveryModel(
        id: 'DL-0095',
        orderRef: 'ORD-4823',
        address: '7 شارع الأرز',
        amount: 21.50,
        state: DeliveryState.waiting,
        createdAt: now.subtract(const Duration(minutes: 8)),
        syncStatus: SyncStatus.synced,
      ),
      DeliveryModel(
        id: 'DL-0096',
        orderRef: 'T-019',
        address: 'استلام من الفرع',
        amount: 18.00,
        state: DeliveryState.delivered,
        driver: 'مروان ر.',
        offline: true,
        settlementStatus: SettlementStatus.pending,
        createdAt: now.subtract(const Duration(minutes: 40)),
        syncStatus: SyncStatus.synced,
      ),
      DeliveryModel(
        id: 'DL-0097',
        orderRef: 'ORD-4818',
        address: '9 شارع الزيتون',
        amount: 44.00,
        state: DeliveryState.delivered,
        driver: 'سارة ك.',
        settlementStatus: SettlementStatus.settled,
        createdAt: now.subtract(const Duration(minutes: 62)),
        syncStatus: SyncStatus.synced,
      ),
    ]);
    final collections = await deliveries.listCollections();
    if (collections.isEmpty) {
      await deliveries.seedCollections([
        CollectionModel(
          id: 'COL-0096',
          deliveryId: 'DL-0096',
          orderRef: 'T-019',
          driver: 'مروان ر.',
          amount: 18.00,
          method: PaymentMethod.cash,
          collectedAt: now.subtract(const Duration(minutes: 32)),
          createdOffline: true,
          settlementStatus: SettlementStatus.pending,
          syncStatus: SyncStatus.synced,
        ),
        CollectionModel(
          id: 'COL-0097',
          deliveryId: 'DL-0097',
          orderRef: 'ORD-4818',
          driver: 'سارة ك.',
          amount: 44.00,
          method: PaymentMethod.cash,
          collectedAt: now.subtract(const Duration(minutes: 55)),
          settlementStatus: SettlementStatus.settled,
          syncStatus: SyncStatus.synced,
        ),
      ]);
    }
  } catch (error, stackTrace) {
    AppLogger.error('Failed to prime delivery data', error, stackTrace);
  }
}

/// Seeds the accounting ledger with the demo transactions when the store is
/// empty, so cash/card totals and approvals are populated in demo mode.
Future<void> _primePaymentData(LocalPaymentRepository? payments) async {
  if (payments == null) return;
  try {
    final cached = await payments.listPayments();
    if (cached.isNotEmpty) return;
    final now = DateTime.now();
    final seeded = <PaymentModel>[];
    final rows = mock.MockData.ledger;
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      seeded.add(
        PaymentModel(
          id: 'seed-${i + 1}',
          orderLocalId: 'seed-${row.ref}',
          orderRef: row.ref,
          amount: row.amount,
          method: row.type == 'نقدي' || row.method == 'نقدي'
              ? PaymentMethod.cash
              : PaymentMethod.card,
          createdAt: now.subtract(Duration(minutes: (rows.length - i) * 6)),
          syncStatus: switch (row.sync) {
            mock.SyncState.local => SyncStatus.localOnly,
            mock.SyncState.pending => SyncStatus.pendingSync,
            mock.SyncState.conflict => SyncStatus.conflict,
            mock.SyncState.synced => SyncStatus.synced,
          },
        ),
      );
    }
    await payments.seedPayments(seeded);
  } catch (error, stackTrace) {
    AppLogger.error('Failed to prime payment data', error, stackTrace);
  }
}

/// Seeds a demo drawer session so the accounting workspace opens with a live
/// session to count and close.
Future<void> _primeCashData(LocalCashSessionRepository? cashSessions) async {
  if (cashSessions == null) return;
  try {
    if ((await cashSessions.listSessions()).isNotEmpty) return;
    final now = DateTime.now();
    await cashSessions.seedSessions([
      CashSession(
        id: 'CS-0001',
        openedAt: now.subtract(const Duration(hours: 3)),
        openingFloat: 200,
        syncStatus: SyncStatus.synced,
      ),
    ]);
  } catch (error, stackTrace) {
    AppLogger.error('Failed to prime cash sessions', error, stackTrace);
  }
}

/// Seeds a pending refund so the approval workflow has something to act on.
Future<void> _primeApprovalData(LocalApprovalRepository? approvals) async {
  if (approvals == null) return;
  try {
    if ((await approvals.listRequests()).isNotEmpty) return;
    final now = DateTime.now();
    await approvals.seedApprovals([
      ApprovalRequest(
        id: 'AP-0001',
        kind: ApprovalKind.refund,
        orderLocalId: 'seed-ORD-4791',
        orderRef: 'ORD-4791',
        amount: 14.50,
        reason: 'طبق مُعاد من العميل',
        requestedAt: now.subtract(const Duration(minutes: 26)),
        createdOffline: true,
        syncStatus: SyncStatus.synced,
      ),
    ]);
  } catch (error, stackTrace) {
    AppLogger.error('Failed to prime approval requests', error, stackTrace);
  }
}

/// Caches a demo release manifest so feature flags and the update card render
/// from the same source the device would use when a backend is present.
Future<void> _primeFeatureFlags(LocalFeatureFlagRepository? features) async {
  if (features == null) return;
  try {
    if (await features.manifest() != null) return;
    await features.cacheManifest(
      ReleaseManifest(
        channel: 'stable',
        version: '0.8.0',
        minSupportedVersion: '0.3.0',
        rolloutPercent: 25,
        mandatory: false,
        publishedAt: DateTime.now(),
        apiContract: AppVersion.apiContract,
        flags: const [
          FeatureFlag(
            key: 'pos_new_layout',
            label: 'تخطيط نقطة البيع الجديد',
            enabled: true,
            scope: 'عام · مفعّل',
          ),
          FeatureFlag(
            key: 'delivery_auto_assign',
            label: 'الإسناد التلقائي للتوصيل',
            enabled: true,
            scope: 'مجموعة 25% · مفعّل',
          ),
          FeatureFlag(
            key: 'settlement_v2',
            label: 'سير عمل التسوية v2',
            enabled: false,
            scope: 'الفرع · متوقف',
          ),
          FeatureFlag(
            key: 'compact_ticket',
            label: 'تنسيق تذكرة مضغوط',
            enabled: true,
            scope: 'الدور · المطبخ',
          ),
          FeatureFlag(
            key: 'inventory_v2',
            label: 'محرك المخزون v2',
            enabled: false,
            scope: 'عام · متوقف',
          ),
        ],
      ),
    );
  } catch (error, stackTrace) {
    AppLogger.error('Failed to cache feature flags', error, stackTrace);
  }
}

/// Seeds inventory items and their opening ledger lines when the store is
/// empty, so on-hand always equals the sum of the movements in demo mode.
Future<void> _primeInventoryData(LocalInventoryRepository? inventory) async {
  if (inventory == null) return;
  try {
    final cached = await inventory.listItems();
    if (cached.isNotEmpty) return;
    final now = DateTime.now();
    final items = <InventoryItemModel>[];
    final movements = <StockMovementModel>[];
    final rows = mock.MockData.inventory;
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final suffix = (i + 1).toString().padLeft(3, '0');
      final id = 'INV-$suffix';
      items.add(
        InventoryItemModel(
          id: id,
          name: row.item,
          unit: row.unit,
          onHand: row.onHand,
          reorderAt: row.reorderAt,
          localRevision: 1,
          syncStatus: SyncStatus.synced,
        ),
      );
      movements.add(
        StockMovementModel(
          id: 'MV-$suffix',
          itemId: id,
          delta: row.onHand,
          reason: StockMovementReason.opening,
          at: now.subtract(Duration(hours: 6 - (i % 6))),
          reference: 'رصيد افتتاحي',
          baseRevision: 1,
          syncStatus: SyncStatus.synced,
        ),
      );
    }
    await inventory.seedItems(items);
    await inventory.seedMovements(movements);
  } catch (error, stackTrace) {
    AppLogger.error('Failed to prime inventory data', error, stackTrace);
  }
}

/// Seeds a supplier directory and a couple of open purchase orders when empty.
///
/// The seeded orders are left `ordered` (not received), so demo stock stays
/// equal to the opening ledger until the user receives an order.
Future<void> _primePurchasingData(
  LocalSupplierRepository? suppliers,
  LocalPurchaseRepository? purchases,
) async {
  if (suppliers == null || purchases == null) return;
  try {
    final cachedSuppliers = await suppliers.listSuppliers();
    if (cachedSuppliers.isEmpty) {
      await suppliers.seedSuppliers([
        SupplierModel(
          id: 'SP-001',
          name: 'مطاحن الشمال',
          phone: '0100 111 2233',
          category: 'حبوب ومعكرونة',
          payable: 1200.0,
          syncStatus: SyncStatus.synced,
        ),
        SupplierModel(
          id: 'SP-002',
          name: 'مزارع الوادي',
          phone: '0100 444 5566',
          category: 'خضروات وألبان',
          syncStatus: SyncStatus.synced,
        ),
        SupplierModel(
          id: 'SP-003',
          name: 'شركة الألبان',
          phone: '0100 777 8899',
          category: 'أجبان وألبان',
          payable: 480.0,
          syncStatus: SyncStatus.synced,
        ),
      ]);
    }
    final cachedPurchases = await purchases.listPurchases();
    if (cachedPurchases.isEmpty) {
      final now = DateTime.now();
      await purchases.seedPurchases([
        PurchaseOrderModel(
          id: 'PO-0001',
          supplierId: 'SP-001',
          supplierName: 'مطاحن الشمال',
          reference: 'PO-2026-0001',
          createdAt: now.subtract(const Duration(days: 2)),
          lines: const [
            PurchaseOrderLine(
              itemId: 'INV-003',
              name: 'باستا (بيني)',
              quantity: 10.0,
              unitCost: 42.0,
            ),
            PurchaseOrderLine(
              itemId: 'INV-002',
              name: 'صلصة الطماطم',
              quantity: 12.0,
              unitCost: 18.0,
            ),
          ],
          syncStatus: SyncStatus.synced,
        ),
        PurchaseOrderModel(
          id: 'PO-0002',
          supplierId: 'SP-003',
          supplierName: 'شركة الألبان',
          reference: 'PO-2026-0002',
          createdAt: now.subtract(const Duration(hours: 20)),
          lines: const [
            PurchaseOrderLine(
              itemId: 'INV-001',
              name: 'موزاريلا',
              quantity: 6.0,
              unitCost: 120.0,
            ),
          ],
          syncStatus: SyncStatus.synced,
        ),
      ]);
    }
  } catch (error, stackTrace) {
    AppLogger.error('Failed to prime purchasing data', error, stackTrace);
  }
}

/// Seeds a small branch network plus the last synced figures for the branches
/// other than this device's, so the consolidated view has something to show in
/// demo mode. The device's own branch is never cached as an aggregate — it is
/// always read live from the local stores.
Future<void> _primeBranchData(LocalBranchRepository? branches) async {
  if (branches == null) return;
  try {
    final cached = await branches.listBranches();
    if (cached.isEmpty) {
      final now = DateTime.now();
      await branches.cacheBranches([
        BranchModel(
          id: 'BR-01',
          name: 'بوابة الشمال',
          code: 'NS-01',
          city: 'القاهرة',
          timezone: 'Africa/Cairo',
          openedAt: now.subtract(const Duration(days: 1100)),
        ),
        BranchModel(
          id: 'BR-02',
          name: 'فرع المعادي',
          code: 'MD-02',
          city: 'القاهرة',
          timezone: 'Africa/Cairo',
          openedAt: now.subtract(const Duration(days: 420)),
        ),
        BranchModel(
          id: 'BR-03',
          name: 'فرع مدينة نصر',
          code: 'NS-03',
          city: 'القاهرة',
          timezone: 'Africa/Cairo',
          openedAt: now.subtract(const Duration(days: 150)),
          status: BranchStatus.paused,
        ),
      ]);
    }
    if (await branches.activeBranch() == null) {
      await branches.setActiveBranch('BR-01');
    }
    if ((await branches.cachedAggregates()).isEmpty) {
      final now = DateTime.now();
      await branches.cacheAggregate(
        BranchRollup(
          branchId: 'BR-02',
          orders: 214,
          sales: 18450.0,
          collected: 17980.5,
          inventoryUnits: 640.0,
          asOf: now.subtract(const Duration(minutes: 40)),
        ),
      );
      await branches.cacheAggregate(
        BranchRollup(
          branchId: 'BR-03',
          orders: 96,
          sales: 7420.25,
          collected: 7010.0,
          inventoryUnits: 388.5,
          asOf: now.subtract(const Duration(hours: 9)),
          pending: 3,
        ),
      );
    }
  } catch (error, stackTrace) {
    AppLogger.error('Failed to prime branch data', error, stackTrace);
  }
}

/// Seeds a cached release manifest for the running platform when none exists, so
/// the update card has a real decision to render in demo mode. Published builds
/// receive this document from the backend; the seed is only a stand-in.
Future<void> _primeUpdateManifest(LocalUpdateRepository? updates) async {
  if (updates == null) return;
  try {
    if (await updates.cached() != null) return;
    final now = DateTime.now();
    await updates.cache(
      UpdateManifest(
        releaseId: 'rel-${AppVersion.channel}-0.9.0',
        version: '0.9.0',
        buildNumber: 2,
        platform: currentUpdatePlatform(),
        channel: currentUpdateChannel(),
        status: ReleaseStatus.active,
        severity: UpdateSeverity.recommended,
        rolloutPercent: 100,
        publishedAt: now,
        artifact: const ReleaseArtifact(
          reference: 'releases/rms-0.9.0.pkg',
          sizeBytes: 48234496,
          sha256:
              'a3f1c8e27d4b9016f8e2a5c7b3d9014e6f2a8c5b1d3e7092fa4c6b8d0e2f4a6c',
          signature: 'rms-release-key',
        ),
        minSupportedVersion: '0.7.0',
        localSchemaMin: 4,
        localSchemaMax: 6,
        requiredMigrationVersion: AppVersion.localSchemaVersion,
        releaseNotes: 'تحسينات في أداء المزامنة والعمل دون اتصال.',
        forceAfter: now.add(const Duration(days: 21)),
      ),
    );
  } catch (error, stackTrace) {
    AppLogger.error('Failed to prime update manifest', error, stackTrace);
  }
}

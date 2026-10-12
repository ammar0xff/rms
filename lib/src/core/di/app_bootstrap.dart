import 'dart:async';

import 'package:firebase_core/firebase_core.dart';

import '../config/firebase_config.dart';
import '../di/app_services.dart';
import '../logging/app_logger.dart';
import '../../data/local/local_database.dart';
import '../../data/local/outbox/outbox_status.dart';
import '../../data/local/outbox/outbox_store.dart';
import '../../data/repositories/demo_auth_repository.dart';
import '../../data/repositories/firebase_auth_repository.dart';
import '../../data/repositories/local_delivery_repository.dart';
import '../../data/repositories/local_kitchen_repository.dart';
import '../../data/repositories/local_menu_repository.dart';
import '../../data/repositories/local_order_repository.dart';
import '../../data/repositories/local_payment_repository.dart';
import '../../domain/models/delivery.dart';
import '../../domain/models/kitchen_ticket.dart';
import '../../domain/models/menu_item.dart';
import '../../domain/models/payment.dart';
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

  return _resolveAuth(config, database);
}

Future<AppServices> _resolveAuth(
  FirebaseConfig config,
  LocalDatabase? database,
) async {
  final outbox = database == null ? null : OutboxStore(database);
  final orders = (database == null || outbox == null)
      ? null
      : LocalOrderRepository(database, outbox: outbox);
  final menu = database == null ? null : LocalMenuRepository(database);
  final kitchen = database == null ? null : LocalKitchenRepository(database);
  final payments = (database == null || outbox == null)
      ? null
      : LocalPaymentRepository(database, outbox: outbox);
  final deliveries = (database == null || outbox == null)
      ? null
      : LocalDeliveryRepository(database, outbox: outbox);
  await _primeMenuCache(menu);
  await _primeKitchenCache(kitchen);
  await _primeDeliveryData(deliveries);
  await _primePaymentData(payments);

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
    );
  }

  try {
    await Firebase.initializeApp(options: config.toOptions());
    AppLogger.info('Firebase initialized (env=${config.environment}).');
    final sync = _buildSync(outbox, orders, payments, deliveries);
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
) {
  if (outbox == null || orders == null) return null;
  final engine = SyncEngine(
    transport: FirestoreSyncTransport(),
    outbox: outbox,
    onApplied: (entry) async {
      await orders.applySynced(entry);
      await payments?.applySynced(entry);
      await deliveries?.applySynced(entry);
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
        state: DeliveryState.collected,
        driver: 'مروان ر.',
        offline: true,
        createdAt: now.subtract(const Duration(minutes: 40)),
        syncStatus: SyncStatus.synced,
      ),
    ]);
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

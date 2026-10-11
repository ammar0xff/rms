import 'dart:async';

import 'package:firebase_core/firebase_core.dart';

import '../config/firebase_config.dart';
import '../di/app_services.dart';
import '../logging/app_logger.dart';
import '../../data/local/local_database.dart';
import '../../data/local/outbox/outbox_store.dart';
import '../../data/repositories/demo_auth_repository.dart';
import '../../data/repositories/firebase_auth_repository.dart';
import '../../data/repositories/local_order_repository.dart';
import '../../data/sync/connectivity_monitor.dart';
import '../../data/sync/firestore_sync_transport.dart';
import '../../data/sync/sync_coordinator.dart';
import '../../data/sync/sync_engine.dart';
import '../../data/sync/sync_service.dart';

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
    );
  }

  try {
    await Firebase.initializeApp(options: config.toOptions());
    AppLogger.info('Firebase initialized (env=${config.environment}).');
    final sync = _buildSync(outbox, orders);
    if (sync != null) unawaited(sync.start());
    return AppServices(
      config: config,
      auth: FirebaseAuthRepository(),
      firebaseReady: true,
      database: database,
      orders: orders,
      sync: sync,
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
    );
  }
}

/// Builds the connectivity-driven sync loop, or null when either the store or
/// the backend half is unavailable.
SyncService? _buildSync(OutboxStore? outbox, LocalOrderRepository? orders) {
  if (outbox == null || orders == null) return null;
  final engine = SyncEngine(
    transport: FirestoreSyncTransport(),
    outbox: outbox,
    onApplied: orders.applySynced,
  );
  return SyncService(
    coordinator: SyncCoordinator(engine: engine),
    connectivity: ConnectivityMonitor(),
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

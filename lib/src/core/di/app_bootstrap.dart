import 'package:firebase_core/firebase_core.dart';

import '../config/firebase_config.dart';
import '../di/app_services.dart';
import '../logging/app_logger.dart';
import '../../data/local/local_database.dart';
import '../../data/repositories/demo_auth_repository.dart';
import '../../data/repositories/firebase_auth_repository.dart';
import '../../data/repositories/local_order_repository.dart';

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
  final orders = database == null ? null : LocalOrderRepository(database);

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
    return AppServices(
      config: config,
      auth: FirebaseAuthRepository(),
      firebaseReady: true,
      database: database,
      orders: orders,
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

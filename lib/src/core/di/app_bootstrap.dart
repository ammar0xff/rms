import 'package:firebase_core/firebase_core.dart';

import '../config/firebase_config.dart';
import '../di/app_services.dart';
import '../logging/app_logger.dart';
import '../../data/repositories/demo_auth_repository.dart';
import '../../data/repositories/firebase_auth_repository.dart';

/// Resolves the app's dependencies. When Firebase is configured and reachable
/// the backend repositories are used; otherwise the app degrades to a fully
/// functional local demo so builds and the live site keep working.
Future<AppServices> bootstrapApp() async {
  final config = FirebaseConfig.fromEnvironment();

  if (!config.isConfigured) {
    AppLogger.warn(
      'Firebase config not provided (dart-defines missing) — running in demo mode.',
    );
    return AppServices(
      config: config,
      auth: DemoAuthRepository(),
      firebaseReady: false,
    );
  }

  try {
    await Firebase.initializeApp(options: config.toOptions());
    AppLogger.info('Firebase initialized (env=${config.environment}).');
    return AppServices(
      config: config,
      auth: FirebaseAuthRepository(),
      firebaseReady: true,
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
    );
  }
}

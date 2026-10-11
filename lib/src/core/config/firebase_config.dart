import 'package:firebase_core/firebase_core.dart';

/// Firebase configuration supplied at build time via `--dart-define`.
///
/// Nothing is committed to the repo; CI/dev pass values through dart-defines
/// (and GitHub Actions secrets for the deploy workflow). When no values are
/// present the app runs in demo mode against [MockData].
class FirebaseConfig {
  const FirebaseConfig({
    required this.apiKey,
    required this.authDomain,
    required this.projectId,
    required this.storageBucket,
    required this.messagingSenderId,
    required this.appId,
    this.measurementId = '',
    this.environment = 'dev',
  });

  const FirebaseConfig.empty()
      : apiKey = '',
        authDomain = '',
        projectId = '',
        storageBucket = '',
        messagingSenderId = '',
        appId = '',
        measurementId = '',
        environment = 'dev';

  final String apiKey;
  final String authDomain;
  final String projectId;
  final String storageBucket;
  final String messagingSenderId;
  final String appId;
  final String measurementId;
  final String environment;

  /// A configuration is usable only when the fields Firebase requires are set.
  bool get isConfigured =>
      apiKey.isNotEmpty && projectId.isNotEmpty && appId.isNotEmpty;

  static FirebaseConfig fromEnvironment() => const FirebaseConfig(
        apiKey: String.fromEnvironment('FIREBASE_API_KEY'),
        authDomain: String.fromEnvironment('FIREBASE_AUTH_DOMAIN'),
        projectId: String.fromEnvironment('FIREBASE_PROJECT_ID'),
        storageBucket: String.fromEnvironment('FIREBASE_STORAGE_BUCKET'),
        messagingSenderId: String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID'),
        appId: String.fromEnvironment('FIREBASE_APP_ID'),
        measurementId: String.fromEnvironment('FIREBASE_MEASUREMENT_ID'),
        environment: String.fromEnvironment('APP_ENV', defaultValue: 'dev'),
      );

  FirebaseOptions toOptions() => FirebaseOptions(
        apiKey: apiKey,
        authDomain: authDomain.isEmpty ? null : authDomain,
        projectId: projectId,
        storageBucket: storageBucket.isEmpty ? null : storageBucket,
        messagingSenderId: messagingSenderId.isEmpty ? null : messagingSenderId,
        appId: appId,
        measurementId: measurementId.isEmpty ? null : measurementId,
      );
}

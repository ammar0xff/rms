import 'package:flutter/widgets.dart';

import '../config/firebase_config.dart';
import '../../data/repositories/auth_repository.dart';

/// Process-wide dependencies resolved once at startup.
class AppServices {
  const AppServices({
    required this.config,
    required this.auth,
    required this.firebaseReady,
  });

  final FirebaseConfig config;
  final AuthRepository auth;

  /// Whether Firebase initialized successfully this session.
  final bool firebaseReady;

  /// True when running without a backend (demo data, local sessions).
  bool get isDemo => !config.isConfigured || !firebaseReady;
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

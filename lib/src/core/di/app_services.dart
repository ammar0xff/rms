import 'package:flutter/widgets.dart';

import '../config/firebase_config.dart';
import '../../data/local/local_database.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/kitchen_repository.dart';
import '../../data/repositories/menu_repository.dart';
import '../../data/repositories/order_repository.dart';
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
    this.sync,
    this.print,
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

  /// Connectivity-driven sync loop, or null when there is no backend/store.
  final SyncService? sync;

  /// Local print service (stub).
  final PrintService? print;

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

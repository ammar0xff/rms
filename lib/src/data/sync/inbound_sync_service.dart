import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:sembast/sembast.dart';

import '../../core/logging/app_logger.dart';
import '../../core/state/sync_monitor.dart';
import '../local/local_database.dart';
import '../local/local_stores.dart';
import '../local/outbox/outbox_store.dart';

/// Real-time inbound synchronizer from Cloud Firestore to the local Sembast store.
///
/// Ensures all terminals, devices, and web instances stay synchronized in real time:
/// - Listens to Firestore collections mirrored across the organisation
/// - Protects local unpushed mutations: never overwrites an entity that has pending outbox work
/// - Updates local stores instantly when changes arrive from other terminals
/// - Signals [SyncMonitor] so UI components re-render immediately
class InboundSyncService {
  InboundSyncService({
    required LocalDatabase database,
    required OutboxStore outbox,
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _db = database,
        _outbox = outbox,
        _firestore = firestore,
        _auth = auth;

  final LocalDatabase _db;
  final OutboxStore _outbox;
  final FirebaseFirestore? _firestore;
  final FirebaseAuth? _auth;

  final List<StreamSubscription> _subscriptions = [];
  StreamSubscription<User?>? _authSubscription;
  bool _active = false;
  bool _hasLoggedBlockWarning = false;

  bool get isActive => _active;

  /// Starts listening for authentication changes and triggers collection listeners
  /// only when an authenticated operator session is active.
  void start() {
    try {
      final auth = _auth ?? FirebaseAuth.instance;
      _authSubscription?.cancel();
      _authSubscription = auth.authStateChanges().listen((user) {
        if (user != null) {
          _startCollectionListeners();
        } else {
          stop();
        }
      });

      if (auth.currentUser != null) {
        _startCollectionListeners();
      }
    } catch (_) {
      // If FirebaseAuth is not initialized or unavailable in this environment, fallback to direct start
      _startCollectionListeners();
    }
  }

  void _startCollectionListeners() {
    if (_active) return;
    _active = true;

    final db = _firestore ?? FirebaseFirestore.instance;

    _listenTo(db, 'orders', LocalStores.orders, 'order');
    _listenTo(db, 'payments', LocalStores.payments, 'payment');
    _listenTo(db, 'deliveries', LocalStores.deliveries, 'delivery');
    _listenTo(db, 'collections', LocalStores.collections, 'collection');
    _listenTo(db, 'kitchenTickets', LocalStores.kitchenTickets, 'kitchenTicket');
    _listenTo(db, 'stockMovements', LocalStores.stockMovements, 'stockMovement');
    _listenTo(db, 'inventoryItems', LocalStores.inventory, 'inventoryItem');
    _listenTo(db, 'cashSessions', LocalStores.cashSessions, 'cashSession');
    _listenTo(db, 'approvals', LocalStores.approvals, 'approval');
    _listenTo(db, 'customers', LocalStores.customers, 'customer');
    _listenTo(db, 'menu', LocalStores.menu, 'menuItem');
    _listenTo(db, 'tables', LocalStores.tables, 'table');
    _listenTo(db, 'purchases', LocalStores.purchases, 'purchase');
    _listenTo(db, 'suppliers', LocalStores.suppliers, 'supplier');
    _listenTo(db, 'drivers', LocalStores.drivers, 'driver');
    _listenTo(db, 'delivery_zones', LocalStores.deliveryZones, 'deliveryZone');
  }

  final Map<String, Completer<void>> _collectionInitialSyncCompleters = {};

  /// Awaits until the initial snapshot pass for [collectionName] has been received
  /// and processed from Cloud Firestore, or until [timeout] elapses.
  Future<void> waitForInitialCollection(
    String collectionName, {
    Duration timeout = const Duration(seconds: 2),
  }) {
    final completer = _collectionInitialSyncCompleters.putIfAbsent(
      collectionName,
      () => Completer<void>(),
    );
    if (completer.isCompleted) return Future.value();
    return completer.future.timeout(timeout, onTimeout: () {});
  }

  void _listenTo(
    FirebaseFirestore firestore,
    String collectionName,
    StoreRef<String, Map<String, Object?>> store,
    String entityType,
  ) {
    final completer = _collectionInitialSyncCompleters.putIfAbsent(
      collectionName,
      () => Completer<void>(),
    );
    try {
      final sub = firestore.collection(collectionName).snapshots().listen(
        (snapshot) async {
          var updated = false;
          for (final change in snapshot.docChanges) {
            final doc = change.doc;
            final entityId = doc.id;
            final data = doc.data();

            if (data == null) continue;

            // Never overwrite if the local client has an unpushed command
            final hasLocalPending = await _outbox.hasOutstandingFor(
              entityType: entityType,
              entityId: entityId,
            );
            if (hasLocalPending) continue;

            // Monotonic LWW check: do not overwrite local state with older remote snapshots
            final existingRecord = await store.record(entityId).get(_db.db);
            if (existingRecord != null && isLocalNewer(existingRecord, data)) {
              continue;
            }

            final record = Map<String, Object?>.from(data)..remove('mirroredAt');
            record.putIfAbsent('id', () => entityId);
            record.putIfAbsent('localId', () => entityId);

            if (change.type == DocumentChangeType.removed) {
              await store.record(entityId).delete(_db.db);
              updated = true;
            } else {
              await store.record(entityId).put(_db.db, record);
              updated = true;
            }
          }
          if (!completer.isCompleted) {
            completer.complete();
          }
          if (updated) {
            SyncMonitor.instance.refresh();
          }
        },
        onError: (err) {
          if (!completer.isCompleted) {
            completer.complete();
          }
          final errStr = err.toString();
          if (errStr.contains('BLOCKED_BY_CLIENT') ||
              errStr.contains('network') ||
              errStr.contains('unavailable') ||
              errStr.contains('permission-denied')) {
            if (!_hasLoggedBlockWarning) {
              _hasLoggedBlockWarning = true;
              AppLogger.warn(
                'Inbound sync network notice: Cloud Firestore stream unavailable ($collectionName). Local offline storage remains fully functional.',
              );
            }
          } else {
            AppLogger.warn('Inbound sync listener for $collectionName: $err');
          }
        },
      );
      _subscriptions.add(sub);
    } catch (e) {
      if (!completer.isCompleted) {
        completer.complete();
      }
      AppLogger.warn('Failed to attach inbound listener to $collectionName: $e');
    }
  }

  /// Stops all active Firestore listeners without canceling the auth listener.
  Future<void> stop() async {
    _active = false;
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();
    _collectionInitialSyncCompleters.clear();
  }

  /// Cancels all active Firestore listeners and auth subscriptions.
  Future<void> dispose() async {
    await _authSubscription?.cancel();
    _authSubscription = null;
    await stop();
  }

  /// Extracts the effective timestamp for Last-Write-Wins (LWW) conflict resolution.
  /// Checks timestamp fields in priority order (mutations before creation).
  static DateTime? extractTimestamp(Map<String, Object?> record) {
    const candidateKeys = [
      'updatedAt',
      'lastModifiedAt',
      'lastModified',
      'closedAt',
      'settledAt',
      'syncedAt',
      'timestamp',
      'createdAt',
      'openedAt',
    ];

    for (final key in candidateKeys) {
      final val = record[key];
      if (val == null) continue;

      if (val is Timestamp) {
        return val.toDate().toUtc();
      }
      if (val is DateTime) {
        return val.toUtc();
      }
      if (val is int) {
        if (val < 10000000000) {
          return DateTime.fromMillisecondsSinceEpoch(val * 1000, isUtc: true);
        }
        return DateTime.fromMillisecondsSinceEpoch(val, isUtc: true);
      }
      if (val is String && val.isNotEmpty) {
        final parsed = DateTime.tryParse(val);
        if (parsed != null) return parsed.toUtc();
      }
    }
    return null;
  }

  /// Returns true if the local record is strictly newer than the incoming remote data.
  /// In that case, the remote update should be discarded to preserve local causality.
  static bool isLocalNewer(Map<String, Object?> local, Map<String, Object?> remote) {
    final localTs = extractTimestamp(local);
    final remoteTs = extractTimestamp(remote);

    if (localTs != null && remoteTs != null) {
      return localTs.isAfter(remoteTs);
    }
    return false;
  }
}

import 'package:sembast/sembast.dart';
import 'package:uuid/uuid.dart';

import '../../core/config/app_version.dart';
import '../../core/logging/app_logger.dart';
import '../../domain/models/delivery.dart';
import '../local/local_database.dart';
import '../local/local_stores.dart';
import '../local/outbox/outbox_entry.dart';
import '../local/outbox/outbox_status.dart';
import '../local/outbox/outbox_store.dart';
import 'delivery_repository.dart';

/// Local-first delivery repository.
///
/// Jobs, driver assignments and state transitions each write their business
/// record and an outbox command in a single transaction, so an offline device
/// can keep dispatching and collecting while the backend is unreachable.
class LocalDeliveryRepository implements DeliveryRepository {
  LocalDeliveryRepository(
    this._db, {
    OutboxStore? outbox,
    Uuid? uuid,
    DateTime Function()? clock,
  })  : _outbox = outbox ?? OutboxStore(_db),
        _uuid = uuid ?? const Uuid(),
        _clock = clock ?? DateTime.now;

  final LocalDatabase _db;
  final OutboxStore _outbox;
  final Uuid _uuid;
  final DateTime Function() _clock;

  @override
  Future<List<DeliveryModel>> listDeliveries() async {
    final snapshots = await LocalStores.deliveries.find(_db.db);
    final deliveries =
        snapshots.map((s) => DeliveryModel.fromRecord(s.value)).toList();
    deliveries.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return deliveries;
  }

  @override
  Future<List<DriverModel>> listDrivers() async {
    final snapshots = await LocalStores.drivers.find(_db.db);
    return snapshots.map((s) => DriverModel.fromRecord(s.value)).toList();
  }

  @override
  Future<void> cacheDrivers(List<DriverModel> drivers, {bool replace = true}) async {
    await _db.transaction((txn) async {
      if (replace) {
        await LocalStores.drivers.delete(txn);
      }
      for (final driver in drivers) {
        await LocalStores.drivers.record(driver.id).put(txn, driver.toRecord());
      }
    });
  }

  @override
  Future<DeliveryModel> createDelivery({
    required String orderRef,
    required String address,
    required double amount,
    bool createdOffline = false,
  }) async {
    final id = _uuid.v4();
    final now = _clock();
    final delivery = DeliveryModel(
      id: id,
      orderRef: orderRef,
      address: address,
      amount: amount,
      state: DeliveryState.waiting,
      createdAt: now,
      offline: createdOffline,
    );
    final entry = OutboxEntry(
      operationId: _uuid.v4(),
      entityType: 'delivery',
      entityId: id,
      operationType: 'createDelivery',
      payload: {
        'id': id,
        'orderRef': orderRef,
        'address': address,
        'amount': amount,
      },
      schemaVersion: AppVersion.localSchemaVersion,
      idempotencyKey: _uuid.v4(),
      createdAt: now,
    );
    await _db.transaction((txn) async {
      await LocalStores.deliveries.record(id).put(txn, delivery.toRecord());
      await _outbox.append(txn, entry);
    });
    return delivery;
  }

  @override
  Future<void> assignDriver(String deliveryId, String driver) =>
      _mutate(
        deliveryId,
        (d) {
          d.driver = driver;
          d.state = DeliveryState.assigned;
        },
        operationType: 'assignDriver',
      );

  @override
  Future<void> updateState(String deliveryId, DeliveryState state) => _mutate(
        deliveryId,
        (d) {
          d.state = state;
        },
        operationType: 'deliveryState',
      );

  /// Applies a local mutation and queues its outbox command atomically.
  Future<void> _mutate(
    String deliveryId,
    void Function(DeliveryModel) change, {
    required String operationType,
  }) async {
    final now = _clock();
    await _db.transaction((txn) async {
      final record = LocalStores.deliveries.record(deliveryId);
      final existing = await record.get(txn);
      if (existing == null) return;
      final delivery = DeliveryModel.fromRecord(existing);
      change(delivery);
      delivery.syncStatus = SyncStatus.pendingSync;
      await record.put(txn, delivery.toRecord());
      await _outbox.append(
        txn,
        OutboxEntry(
          operationId: _uuid.v4(),
          entityType: 'delivery',
          entityId: deliveryId,
          operationType: operationType,
          payload: {
            'id': deliveryId,
            'orderRef': delivery.orderRef,
            'driver': delivery.driver,
            'state': delivery.state.name,
          },
          schemaVersion: AppVersion.localSchemaVersion,
          idempotencyKey: _uuid.v4(),
          createdAt: now,
        ),
      );
    });
  }

  /// Marks the delivery an outbox entry refers to as synced.
  Future<void> applySynced(OutboxEntry entry) async {
    if (entry.entityType != 'delivery') return;
    final record = LocalStores.deliveries.record(entry.entityId);
    final existing = await record.get(_db.db);
    if (existing == null) return;
    final delivery = DeliveryModel.fromRecord(existing);
    delivery.syncStatus = SyncStatus.synced;
    await record.put(_db.db, delivery.toRecord());
  }

  Future<void> seedDeliveries(List<DeliveryModel> deliveries) async {
    if (deliveries.isEmpty) return;
    await _db.transaction((txn) async {
      for (final delivery in deliveries) {
        await LocalStores.deliveries
            .record(delivery.id)
            .put(txn, delivery.toRecord());
      }
    });
    AppLogger.info('Seeded ${deliveries.length} demo deliveries.');
  }
}

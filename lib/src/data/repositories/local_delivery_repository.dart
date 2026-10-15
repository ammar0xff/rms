import 'package:sembast/sembast.dart';
import 'package:uuid/uuid.dart';

import '../../core/config/app_version.dart';
import '../../core/logging/app_logger.dart';
import '../../domain/assignment/delivery_assignment.dart';
import '../../domain/models/audit_entry.dart';
import '../../domain/models/collection.dart';
import '../../domain/models/delivery.dart';
import '../../domain/models/payment.dart';
import '../local/audit_log.dart';
import '../local/local_database.dart';
import '../local/local_stores.dart';
import '../local/outbox/outbox_entry.dart';
import '../local/outbox/outbox_status.dart';
import '../local/outbox/outbox_store.dart';
import 'delivery_repository.dart';

/// Local-first delivery repository.
///
/// Jobs, driver assignments, state transitions and collections each write their
/// business record and an outbox command in a single transaction, so an offline
/// device can keep dispatching, delivering and collecting while the backend is
/// unreachable. Operational state, collection and settlement are tracked
/// separately; only a server acknowledgement settles money.
class LocalDeliveryRepository implements DeliveryRepository {
  LocalDeliveryRepository(
    this._db, {
    OutboxStore? outbox,
    AuditLog? audit,
    Uuid? uuid,
    DateTime Function()? clock,
  })  : _outbox = outbox ?? OutboxStore(_db),
        _audit = audit ?? AuditLog(_db),
        _uuid = uuid ?? const Uuid(),
        _clock = clock ?? DateTime.now;

  final LocalDatabase _db;
  final OutboxStore _outbox;
  final AuditLog _audit;
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
  Future<List<CollectionModel>> listCollections() async {
    final snapshots = await LocalStores.collections.find(_db.db);
    final collections =
        snapshots.map((s) => CollectionModel.fromRecord(s.value)).toList();
    collections.sort((a, b) => a.collectedAt.compareTo(b.collectedAt));
    return collections;
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
    await _db.transaction((txn) async {
      await LocalStores.deliveries.record(id).put(txn, delivery.toRecord());
      await _outbox.append(
        txn,
        _entry(
          entityId: id,
          operationType: 'createDelivery',
          createdAt: now,
          payload: {
            'id': id,
            'orderRef': orderRef,
            'address': address,
            'amount': amount,
          },
        ),
      );
    });
    return delivery;
  }

  @override
  Future<AssignmentOutcome> assignDriver(
    String deliveryId,
    String driver, {
    String? baseDriver,
  }) async {
    final now = _clock();
    var outcome = AssignmentOutcome.assigned;
    await _db.transaction((txn) async {
      final record = LocalStores.deliveries.record(deliveryId);
      final existing = await record.get(txn);
      if (existing == null) return;
      outcome = await _applyAssignment(
        txn,
        DeliveryModel.fromRecord(existing),
        driver,
        now,
        baseDriver: baseDriver,
      );
    });
    return outcome;
  }

  @override
  Future<List<DeliveryAssignmentResult>> autoAssignWaiting() async {
    final now = _clock();
    final results = <DeliveryAssignmentResult>[];
    await _db.transaction((txn) async {
      final deliveries = (await LocalStores.deliveries.find(txn))
          .map((s) => DeliveryModel.fromRecord(s.value))
          .toList();
      final drivers = (await LocalStores.drivers.find(txn))
          .map((s) => DriverModel.fromRecord(s.value))
          .toList();

      final plan = DeliveryAssignmentPolicy.plan(
        deliveries: deliveries,
        drivers: drivers,
      );
      if (plan.isEmpty) return;

      final byId = {for (final delivery in deliveries) delivery.id: delivery};
      for (final planned in plan) {
        final delivery = byId[planned.deliveryId];
        // Re-check the state in case the plan is applied against a snapshot that
        // already assigned the job; never stomp a non-waiting job.
        if (delivery == null || delivery.state != DeliveryState.waiting) continue;
        final outcome =
            await _applyAssignment(txn, delivery, planned.driver, now);
        results.add(
          DeliveryAssignmentResult(
            deliveryId: planned.deliveryId,
            driver: planned.driver,
            outcome: outcome,
          ),
        );
      }
    });
    return results;
  }

  /// Applies one provisional assignment and queues its outbox command.
  ///
  /// Shared by the single-job [assignDriver] and the batch
  /// [autoAssignWaiting] so both honour the same conflict-aware rule: when the
  /// caller's [baseDriver] no longer matches a job that already has a driver,
  /// the reassignment is recorded as a conflict instead of overwriting it.
  Future<AssignmentOutcome> _applyAssignment(
    Transaction txn,
    DeliveryModel delivery,
    String driver,
    DateTime now, {
    String? baseDriver,
  }) async {
    final record = LocalStores.deliveries.record(delivery.id);

    // Conflict-aware reassignment: the caller's snapshot is stale when the
    // stored job already has a *different, non-empty* driver.
    final stale = baseDriver != null &&
        baseDriver != delivery.driver &&
        !delivery.isUnassigned;
    if (stale) {
      delivery.localRevision += 1;
      delivery.syncStatus = SyncStatus.conflict;
      await record.put(txn, delivery.toRecord());
      await _outbox.append(
        txn,
        _entry(
          entityId: delivery.id,
          operationType: 'reassignDeliveryConflict',
          createdAt: now,
          status: OutboxStatus.conflict,
          payload: {
            'id': delivery.id,
            'orderRef': delivery.orderRef,
            'baseDriver': baseDriver,
            'currentDriver': delivery.driver,
            'attemptedDriver': driver,
          },
        ),
      );
      await _audit.append(
        txn,
        AuditEntry(
          id: _uuid.v4(),
          action: AuditAction.reassignConflict,
          entityType: 'delivery',
          entityId: delivery.id,
          summary: 'تعارض إسناد: الحالي ${delivery.driver} مقابل $driver',
          at: now,
          createdOffline: true,
        ),
      );
      return AssignmentOutcome.conflict;
    }

    delivery.driver = driver;
    delivery.state = DeliveryState.assigned;
    delivery.localRevision += 1;
    delivery.syncStatus = SyncStatus.pendingSync;
    await record.put(txn, delivery.toRecord());
    await _outbox.append(
      txn,
      _entry(
        entityId: delivery.id,
        operationType: 'assignDriver',
        createdAt: now,
        payload: {
          'id': delivery.id,
          'orderRef': delivery.orderRef,
          'driver': driver,
          'state': delivery.state.name,
        },
      ),
    );
    return AssignmentOutcome.assigned;
  }

  @override
  Future<void> updateState(String deliveryId, DeliveryState state) async {
    final now = _clock();
    await _db.transaction((txn) async {
      final record = LocalStores.deliveries.record(deliveryId);
      final existing = await record.get(txn);
      if (existing == null) return;
      final delivery = DeliveryModel.fromRecord(existing);
      // Deliveries move forward only: waiting → assigned → onRoute →
      // delivered. Reopening a delivered run would un-collect settled money,
      // so backward transitions throw instead of silently corrupting state.
      if (state.index < delivery.state.index) {
        throw StateError(
          'illegal delivery transition ${delivery.state.name} -> ${state.name}',
        );
      }
      delivery.state = state;
      delivery.localRevision += 1;
      delivery.syncStatus = SyncStatus.pendingSync;
      await record.put(txn, delivery.toRecord());
      await _outbox.append(
        txn,
        _entry(
          entityId: deliveryId,
          operationType: 'deliveryState',
          createdAt: now,
          payload: {
            'id': deliveryId,
            'orderRef': delivery.orderRef,
            'driver': delivery.driver,
            'state': delivery.state.name,
          },
        ),
      );
    });
  }

  @override
  Future<CollectionModel?> recordCollection({
    required String deliveryId,
    required double amount,
    PaymentMethod method = PaymentMethod.cash,
    bool createdOffline = false,
  }) async {
    final now = _clock();
    final id = _uuid.v4();
    CollectionModel? collection;
    await _db.transaction((txn) async {
      final record = LocalStores.deliveries.record(deliveryId);
      final existing = await record.get(txn);
      if (existing == null) return;
      final delivery = DeliveryModel.fromRecord(existing);
      if (!delivery.state.isDelivered) return;

      // One collection per job: recording is idempotent and never duplicates.
      final already = await LocalStores.collections.find(
        txn,
        finder: Finder(filter: Filter.equals('deliveryId', deliveryId)),
      );
      if (already.isNotEmpty) return;

      collection = CollectionModel(
        id: id,
        deliveryId: deliveryId,
        orderRef: delivery.orderRef,
        driver: delivery.driver,
        amount: amount,
        method: method,
        collectedAt: now,
        createdOffline: createdOffline,
      );
      delivery.settlementStatus = SettlementStatus.pending;
      delivery.localRevision += 1;
      delivery.syncStatus = SyncStatus.pendingSync;
      await record.put(txn, delivery.toRecord());
      await LocalStores.collections
          .record(id)
          .put(txn, collection!.toRecord());
      await _outbox.append(
        txn,
        _entry(
          entityType: 'collection',
          entityId: id,
          operationType: 'recordCollection',
          createdAt: now,
          payload: {
            'id': id,
            'deliveryId': deliveryId,
            'orderRef': delivery.orderRef,
            'driver': delivery.driver,
            'amount': amount,
            'method': method.name,
          },
        ),
      );
      await _audit.append(
        txn,
        AuditEntry(
          id: _uuid.v4(),
          action: AuditAction.recordCollection,
          entityType: 'collection',
          entityId: id,
          summary: 'تحصيل ${amount.toStringAsFixed(2)} · ${delivery.orderRef}',
          at: now,
          amount: amount,
          createdOffline: createdOffline,
        ),
      );
    });
    return collection;
  }

  @override
  Future<void> finalizeSettlement(String deliveryId) async {
    final now = _clock();
    await _db.transaction((txn) async {
      // Idempotent: never queue a second settlement for the same job. The
      // check lives INSIDE the transaction — a pre-check outside lets two
      // concurrent calls both pass and append two settles with distinct
      // idempotency keys, which the server-side dedupe cannot collapse.
      final queued = await LocalStores.outbox.find(
        txn,
        finder: Finder(
          filter: Filter.and([
            Filter.equals('entityType', 'delivery'),
            Filter.equals('entityId', deliveryId),
            Filter.equals('operationType', 'settleDelivery'),
            Filter.inList('syncStatus', [
              OutboxStatus.pending.name,
              OutboxStatus.inProgress.name,
              OutboxStatus.retryableFailure.name,
            ]),
          ]),
        ),
      );
      if (queued.isNotEmpty) return;

      final record = LocalStores.deliveries.record(deliveryId);
      final existing = await record.get(txn);
      if (existing == null) return;
      final delivery = DeliveryModel.fromRecord(existing);
      if (!delivery.state.isDelivered) return;
      if (delivery.settlementStatus == SettlementStatus.settled) return;

      final pending = await LocalStores.collections.find(
        txn,
        finder: Finder(
          filter: Filter.and([
            Filter.equals('deliveryId', deliveryId),
            Filter.equals('settlementStatus', SettlementStatus.pending.name),
          ]),
        ),
      );
      final outstanding = pending.fold<double>(
        0,
        (sum, s) => sum + ((s.value['amount'] as num?)?.toDouble() ?? 0),
      );

      await _outbox.append(
        txn,
        _entry(
          entityId: deliveryId,
          operationType: 'settleDelivery',
          createdAt: now,
          payload: {
            'id': deliveryId,
            'orderRef': delivery.orderRef,
            'settlement': outstanding,
          },
        ),
      );
    });
  }

  /// Marks the delivery (or collection) an outbox entry refers to as synced and
  /// applies any server-confirmed settlement.
  Future<void> applySynced(OutboxEntry entry) async {
    if (entry.entityType == 'collection') {
      final record = LocalStores.collections.record(entry.entityId);
      final existing = await record.get(_db.db);
      if (existing == null) return;
      final collection = CollectionModel.fromRecord(existing);
      collection.syncStatus = SyncStatus.synced;
      await record.put(_db.db, collection.toRecord());
      // Recording a collection dirties its delivery, but queues no delivery
      // command — so no delivery ack ever clears the flag. Clear it here when
      // nothing else for this delivery is still outstanding; otherwise the
      // delivery reads pendingSync indefinitely for work already pushed.
      final deliveryId = entry.payload['deliveryId'];
      if (deliveryId is String) {
        await _clearDeliveryFlagWhenQuiet(deliveryId);
      }
      return;
    }
    if (entry.entityType != 'delivery') return;
    final record = LocalStores.deliveries.record(entry.entityId);
    final existing = await record.get(_db.db);
    if (existing == null) return;
    final delivery = DeliveryModel.fromRecord(existing);
    if (!await _outbox.hasOutstandingFor(entityType: 'delivery', entityId: entry.entityId)) {
      delivery.syncStatus = SyncStatus.synced;
    }
    if (entry.operationType == 'settleDelivery') {
      delivery.settlementStatus = SettlementStatus.settled;
      await _settleCollections(entry.entityId);
      await _audit.record(
        AuditEntry(
          id: _uuid.v4(),
          action: AuditAction.settleDelivery,
          entityType: 'delivery',
          entityId: entry.entityId,
          summary: 'تسوية معتمدة من الخادم · ${delivery.orderRef}',
          at: _clock(),
          amount: delivery.amount,
        ),
      );
    }
    await record.put(_db.db, delivery.toRecord());
  }

  /// Clears the delivery's dirty flag once nothing for it remains unsynced.
  ///
  /// Some writes (recording a collection) dirty the delivery without queueing
  /// a delivery command of their own. The flag must clear when the commands
  /// that do exist are acknowledged — but only then: while any delivery or
  /// collection command for this job is still outstanding, the flag stays.
  Future<void> _clearDeliveryFlagWhenQuiet(String deliveryId) async {
    final entries = await _outbox.all();
    final outstanding = entries.any((e) =>
        e.syncStatus != OutboxStatus.synced &&
        ((e.entityType == 'delivery' && e.entityId == deliveryId) ||
            (e.entityType == 'collection' &&
                e.payload['deliveryId'] == deliveryId)));
    if (outstanding) return;
    final record = LocalStores.deliveries.record(deliveryId);
    final existing = await record.get(_db.db);
    if (existing == null) return;
    final delivery = DeliveryModel.fromRecord(existing);
    if (delivery.syncStatus == SyncStatus.synced) return;
    delivery.syncStatus = SyncStatus.synced;
    await record.put(_db.db, delivery.toRecord());
  }

  /// Marks every still-pending collection of a job as settled.
  Future<void> _settleCollections(String deliveryId) async {    await _db.transaction((txn) async {
      final snapshots = await LocalStores.collections.find(
        txn,
        finder: Finder(filter: Filter.equals('deliveryId', deliveryId)),
      );
      for (final snapshot in snapshots) {
        final collection = CollectionModel.fromRecord(snapshot.value);
        if (collection.settlementStatus == SettlementStatus.settled) continue;
        collection.settlementStatus = SettlementStatus.settled;
        collection.syncStatus = SyncStatus.synced;
        await LocalStores.collections
            .record(collection.id)
            .put(txn, collection.toRecord());
      }
    });
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

  Future<void> seedCollections(List<CollectionModel> collections) async {
    if (collections.isEmpty) return;
    await _db.transaction((txn) async {
      for (final collection in collections) {
        await LocalStores.collections
            .record(collection.id)
            .put(txn, collection.toRecord());
      }
    });
    AppLogger.info('Seeded ${collections.length} demo collections.');
  }

  OutboxEntry _entry({
    String entityType = 'delivery',
    required String entityId,
    required String operationType,
    required DateTime createdAt,
    required Map<String, Object?> payload,
    OutboxStatus status = OutboxStatus.pending,
  }) =>
      OutboxEntry(
        operationId: _uuid.v4(),
        entityType: entityType,
        entityId: entityId,
        operationType: operationType,
        payload: Map<String, dynamic>.from(payload),
        schemaVersion: AppVersion.localSchemaVersion,
        idempotencyKey: _uuid.v4(),
        createdAt: createdAt,
        syncStatus: status,
      );
}

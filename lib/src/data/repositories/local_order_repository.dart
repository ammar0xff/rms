import 'package:sembast/sembast.dart';
import 'package:uuid/uuid.dart';

import '../../core/config/app_version.dart';
import '../../core/logging/app_logger.dart';
import '../../domain/models/menu_item.dart';
import '../../domain/models/order.dart';
import '../../domain/models/order_draft.dart';
import '../../domain/models/stock_movement.dart';
import '../local/local_database.dart';
import '../local/local_stores.dart';
import '../local/outbox/outbox_entry.dart';
import '../local/outbox/outbox_status.dart';
import '../local/outbox/outbox_store.dart';
import '../sync/record_mirror.dart';
import '../sync/sync_ack.dart';
import 'local_inventory_repository.dart';
import 'order_repository.dart';

/// Local-first order repository backed by the on-device store.
///
/// [createOrder] writes the order record and its outbox entry in a single
/// transaction, so a crash can never leave an unsynced order without a matching
/// sync command (or a sync command for an order that does not exist).
class LocalOrderRepository implements OrderRepository {
  LocalOrderRepository(
    this._db, {
    OutboxStore? outbox,
    Uuid? uuid,
    DateTime Function()? clock,
    RecordMirror? mirror,
    LocalInventoryRepository? inventory,
  })  : _outbox = outbox ?? OutboxStore(_db),
        _uuid = uuid ?? const Uuid(),
        _clock = clock ?? DateTime.now,
        _mirror = mirror,
        _inventory = inventory;

  final LocalDatabase _db;
  final OutboxStore _outbox;
  final Uuid _uuid;
  final DateTime Function() _clock;

  /// Best-effort data mirror (see [RecordMirror]). Null outside Firebase
  /// mode, where there is nowhere to mirror to.
  final RecordMirror? _mirror;
  final LocalInventoryRepository? _inventory;

  @override
  Future<Order> createOrder(OrderDraft draft) async {
    final localId = _uuid.v4();
    final now = _clock();
    final order = Order(
      localId: localId,
      provisionalOrderNumber: _provisionalNumber(now, localId),
      items: draft.items,
      createdOffline: draft.createdOffline,
      createdAt: now,
      orderType: draft.orderType,
      taxAmount: draft.taxAmount,
      discountAmount: draft.discountAmount,
      serviceAmount: draft.serviceAmount,
      deliveryFee: draft.deliveryFee,
      customerId: draft.customerId,
      customerName: draft.customerName,
      customerPhone: draft.customerPhone,
      deliveryAddress: draft.deliveryAddress,
      deliveryLatitude: draft.deliveryLatitude,
      deliveryLongitude: draft.deliveryLongitude,
      branchId: draft.branchId,
      syncStatus: SyncStatus.pendingSync,
    );
    final entry = OutboxEntry(
      operationId: _uuid.v4(),
      entityType: 'order',
      entityId: localId,
      operationType: 'createOrder',
      payload: {
        'localId': localId,
        'items': order.items.map((i) => i.toRecord()).toList(),
        'orderType': order.orderType.name,
        'total': order.total,
        if (order.customerId != null) 'customerId': order.customerId,
        if (order.customerName != null) 'customerName': order.customerName,
        if (order.customerPhone != null) 'customerPhone': order.customerPhone,
        if (order.deliveryAddress != null) 'deliveryAddress': order.deliveryAddress,
        if (order.deliveryLatitude != null) 'deliveryLatitude': order.deliveryLatitude,
        if (order.deliveryLongitude != null) 'deliveryLongitude': order.deliveryLongitude,
        if (order.branchId != null) 'branchId': order.branchId,
      },
      schemaVersion: AppVersion.localSchemaVersion,
      idempotencyKey: _uuid.v4(),
      createdAt: now,
    );

    await _db.transaction((txn) async {
      await LocalStores.orders.record(localId).put(txn, order.toRecord());
      await _outbox.append(txn, entry);
      if (_inventory != null) {
        await _depleteRecipeIngredients(txn, order);
      }
    });
    AppLogger.info('Order $localId queued (offline=${draft.createdOffline}).');
    return order;
  }

  Future<void> _depleteRecipeIngredients(Transaction txn, Order order) async {
    final inventory = _inventory;
    if (inventory == null) return;

    for (final item in order.items) {
      if (item.productId.isEmpty) continue;
      final menuRecord = await LocalStores.menu.record(item.productId).get(txn);
      if (menuRecord == null) continue;

      final rawRecipe = menuRecord['recipe'] as List?;
      if (rawRecipe == null || rawRecipe.isEmpty) continue;

      final ingredients = rawRecipe
          .map((e) => RecipeIngredient.fromRecord(Map<String, Object?>.from(e as Map)))
          .toList();

      for (final ingredient in ingredients) {
        final totalDelta = -(ingredient.quantity * item.quantity);
        if (totalDelta == 0) continue;

        try {
          await inventory.postMovement(
            txn,
            itemId: ingredient.inventoryItemId,
            delta: totalDelta,
            reason: StockMovementReason.sale,
            reference: 'order:${order.localId}',
            createdOffline: order.createdOffline,
          );
        } catch (e) {
          AppLogger.warn(
            'Could not deplete inventory item ${ingredient.inventoryItemId} for order ${order.localId}: $e',
          );
        }
      }
    }
  }

  @override
  Future<List<Order>> listOrders({String? branchId, String? customerId}) async {
    final snapshots = await LocalStores.orders.find(_db.db);
    var orders = <Order>[];
    for (final s in snapshots) {
      try {
        orders.add(Order.fromRecord(s.value));
      } catch (e) {
        AppLogger.warn('Skipping corrupted order record ${s.key}: $e');
      }
    }
    if (branchId != null && branchId.isNotEmpty) {
      orders = orders.where((o) => o.branchId == null || o.branchId!.isEmpty || o.branchId == branchId).toList();
    }
    if (customerId != null && customerId.isNotEmpty) {
      orders = orders.where((o) => o.customerId == customerId).toList();
    }
    orders.sort(
      (a, b) => b.createdAt.compareTo(a.createdAt),
    );
    return orders;
  }

  @override
  Future<List<Order>> getOrdersByCustomer(String customerId) async {
    return listOrders(customerId: customerId);
  }

  @override
  Future<List<Order>> getOrdersByBranch(String branchId) async {
    return listOrders(branchId: branchId);
  }

  @override
  Stream<List<Order>> watchOrders() {
    return LocalStores.orders.query().onSnapshots(_db.db).map((snapshots) {
      final orders = <Order>[];
      for (final s in snapshots) {
        try {
          orders.add(Order.fromRecord(s.value));
        } catch (e) {
          AppLogger.warn('Skipping corrupted order record ${s.key}: $e');
        }
      }
      orders.sort(
        (a, b) => b.createdAt.compareTo(a.createdAt),
      );
      return orders;
    });
  }

  @override
  Future<Order?> rerouteOrder({
    required String orderId,
    required String targetBranchId,
  }) async {
    final now = _clock();
    final record = LocalStores.orders.record(orderId);
    Order? updated;

    await _db.transaction((txn) async {
      final existing = await record.get(txn);
      if (existing == null) return;

      final current = Order.fromRecord(existing);
      final newRevision = current.localRevision + 1;
      final payload = Map<String, Object?>.from(existing);
      payload['branchId'] = targetBranchId;
      payload['localRevision'] = newRevision;
      payload['syncStatus'] = SyncStatus.pendingSync.name;
      payload['updatedAt'] = now.toIso8601String();

      await record.put(txn, payload);
      updated = Order.fromRecord(payload);

      final entry = OutboxEntry(
        operationId: _uuid.v4(),
        entityType: 'order',
        entityId: orderId,
        operationType: 'rerouteOrder',
        payload: {
          'id': orderId,
          'targetBranchId': targetBranchId,
          'localRevision': newRevision,
          'updatedAt': now.toIso8601String(),
        },
        schemaVersion: AppVersion.localSchemaVersion,
        idempotencyKey: _uuid.v4(),
        createdAt: now,
      );
      await _outbox.append(txn, entry);
    });

    if (updated != null) {
      await mirrorRecord(
        _mirror,
        entityType: 'order',
        entityId: orderId,
        snapshot: updated!.toRecord(),
      );
      AppLogger.info('Order $orderId rerouted to branch $targetBranchId.');
    }

    return updated;
  }

  /// Applies a sync acknowledgement to the order an outbox entry refers to.
  /// Used as the [SyncEngine]'s `onApplied` callback.
  Future<void> applySynced(OutboxEntry entry) async {
    if (entry.entityType != 'order') return;
    final record = LocalStores.orders.record(entry.entityId);
    final existing = await record.get(_db.db);
    if (existing == null) return;
    final order = Order.fromRecord(existing);
    // Server identity folds in regardless; the dirty flag clears only when
    // no newer command for this order is still outstanding.
    if (!await _outbox.hasOutstandingFor(entityType: 'order', entityId: entry.entityId)) {
      order.syncStatus = SyncStatus.synced;
    }
    final serverId = SyncAckReader.serverId(entry.payload);
    if (serverId != null) order.serverId = serverId;
    final canonicalOrderNumber = SyncAckReader.canonicalOrderNumber(entry.payload);
    if (canonicalOrderNumber != null) {
      order.canonicalOrderNumber = canonicalOrderNumber;
    }
    await record.put(_db.db, order.toRecord());
    await mirrorRecord(_mirror, 
      entityType: 'order',
      entityId: entry.entityId,
      snapshot: order.toRecord(),
    );
  }

  String _provisionalNumber(DateTime now, String localId) {
    final date = '${now.year.toString().padLeft(4, '0')}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}';
    final suffix = localId.replaceAll('-', '').substring(0, 6).toUpperCase();
    return 'O-$date-$suffix';
  }
}

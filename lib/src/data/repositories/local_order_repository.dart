import 'package:sembast/sembast.dart';
import 'package:uuid/uuid.dart';

import '../../core/config/app_version.dart';
import '../../core/logging/app_logger.dart';
import '../../domain/models/order.dart';
import '../../domain/models/order_draft.dart';
import '../local/local_database.dart';
import '../local/local_stores.dart';
import '../local/outbox/outbox_entry.dart';
import '../local/outbox/outbox_status.dart';
import '../local/outbox/outbox_store.dart';
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
  })  : _outbox = outbox ?? OutboxStore(_db),
        _uuid = uuid ?? const Uuid(),
        _clock = clock ?? DateTime.now;

  final LocalDatabase _db;
  final OutboxStore _outbox;
  final Uuid _uuid;
  final DateTime Function() _clock;

  @override
  Future<Order> createOrder(OrderDraft draft) async {
    final localId = _uuid.v4();
    final now = _clock();
    final order = Order(
      localId: localId,
      provisionalOrderNumber: _provisionalNumber(now, localId),
      items: draft.items,
      createdOffline: draft.createdOffline,
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
        'total': order.total,
      },
      schemaVersion: AppVersion.localSchemaVersion,
      idempotencyKey: _uuid.v4(),
      createdAt: now,
    );

    await _db.transaction((txn) async {
      await LocalStores.orders.record(localId).put(txn, order.toRecord());
      await _outbox.append(txn, entry);
    });
    AppLogger.info('Order $localId queued (offline=${draft.createdOffline}).');
    return order;
  }

  @override
  Future<List<Order>> listOrders() async {
    final snapshots = await LocalStores.orders.find(_db.db);
    final orders = snapshots.map((s) => Order.fromRecord(s.value)).toList();
    orders.sort(
      (a, b) => a.provisionalOrderNumber.compareTo(b.provisionalOrderNumber),
    );
    return orders;
  }

  /// Applies a sync acknowledgement to the order an outbox entry refers to.
  /// Used as the [SyncEngine]'s `onApplied` callback.
  Future<void> applySynced(OutboxEntry entry) async {
    if (entry.entityType != 'order') return;
    final record = LocalStores.orders.record(entry.entityId);
    final existing = await record.get(_db.db);
    if (existing == null) return;
    final order = Order.fromRecord(existing);
    order.syncStatus = SyncStatus.synced;
    final serverId = entry.payload['serverId'] as String?;
    if (serverId != null) order.serverId = serverId;
    final canonicalOrderNumber = entry.payload['canonicalOrderNumber'] as String?;
    if (canonicalOrderNumber != null) {
      order.canonicalOrderNumber = canonicalOrderNumber;
    }
    await record.put(_db.db, order.toRecord());
  }

  String _provisionalNumber(DateTime now, String localId) {
    final date = '${now.year.toString().padLeft(4, '0')}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}';
    final suffix = localId.replaceAll('-', '').substring(0, 6).toUpperCase();
    return 'O-$date-$suffix';
  }
}

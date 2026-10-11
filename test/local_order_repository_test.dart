import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/data/local/local_database.dart';
import 'package:rms/src/data/local/outbox/outbox_entry.dart';
import 'package:rms/src/data/local/outbox/outbox_status.dart';
import 'package:rms/src/data/local/outbox/outbox_store.dart';
import 'package:rms/src/data/repositories/local_order_repository.dart';
import 'package:rms/src/domain/models/order.dart';
import 'package:rms/src/domain/models/order_draft.dart';

const List<OrderItem> _items = [
  OrderItem(productId: 'p1', name: 'برجر', unitPrice: 45, quantity: 2),
];

void main() {
  late LocalDatabase db;
  late LocalOrderRepository repo;

  setUp(() async {
    db = await LocalDatabase.memory();
    repo = LocalOrderRepository(db, clock: () => DateTime(2026, 10, 11, 12));
  });

  tearDown(() => db.close());

  test('starts with no orders', () async {
    expect(await repo.listOrders(), isEmpty);
  });

  test('creates a pending order with a provisional number and outbox entry',
      () async {
    final order = await repo.createOrder(
      const OrderDraft(items: _items, createdOffline: true),
    );

    expect(order.syncStatus, SyncStatus.pendingSync);
    expect(order.createdOffline, isTrue);
    expect(order.provisionalOrderNumber, startsWith('O-20261011-'));
    final suffix = order.localId.replaceAll('-', '').substring(0, 6).toUpperCase();
    expect(order.provisionalOrderNumber, endsWith(suffix));

    final stored = await repo.listOrders();
    expect(stored, hasLength(1));
    expect(stored.single.localId, order.localId);

    final entry = (await OutboxStore(db).all()).single;
    expect(entry.operationType, 'createOrder');
    expect(entry.entityType, 'order');
    expect(entry.entityId, order.localId);
    expect(entry.idempotencyKey, isNotEmpty);
    expect(entry.payload['localId'], order.localId);
  });

  test('lists orders sorted by provisional number', () async {
    for (var i = 0; i < 5; i++) {
      await repo.createOrder(const OrderDraft(items: _items));
    }
    final numbers =
        (await repo.listOrders()).map((o) => o.provisionalOrderNumber).toList();
    expect(numbers, hasLength(5));
    final sorted = [...numbers]..sort();
    expect(numbers, sorted);
  });

  test('applySynced marks the order synced and records server identity',
      () async {
    final order = await repo.createOrder(const OrderDraft(items: _items));
    await repo.applySynced(OutboxEntry(
      operationId: 'op',
      entityType: 'order',
      entityId: order.localId,
      operationType: 'createOrder',
      payload: const {'serverId': 'srv-1', 'canonicalOrderNumber': 'ORD-9'},
      schemaVersion: 1,
      idempotencyKey: 'k',
      createdAt: DateTime.utc(2026, 1, 1),
    ));

    final stored = (await repo.listOrders()).single;
    expect(stored.syncStatus, SyncStatus.synced);
    expect(stored.serverId, 'srv-1');
    expect(stored.canonicalOrderNumber, 'ORD-9');
  });

  test('applySynced ignores other entities and unknown orders', () async {
    await repo.applySynced(OutboxEntry(
      operationId: 'a',
      entityType: 'customer',
      entityId: 'c1',
      operationType: 'createCustomer',
      payload: const {},
      schemaVersion: 1,
      idempotencyKey: 'k1',
      createdAt: DateTime.utc(2026, 1, 1),
    ));
    await repo.applySynced(OutboxEntry(
      operationId: 'b',
      entityType: 'order',
      entityId: 'missing',
      operationType: 'createOrder',
      payload: const {},
      schemaVersion: 1,
      idempotencyKey: 'k2',
      createdAt: DateTime.utc(2026, 1, 1),
    ));
    expect(await repo.listOrders(), isEmpty);
  });
}

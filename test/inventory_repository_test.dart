import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/data/local/audit_log.dart';
import 'package:rms/src/data/local/local_database.dart';
import 'package:rms/src/data/local/outbox/outbox_status.dart';
import 'package:rms/src/data/local/outbox/outbox_store.dart';
import 'package:rms/src/data/repositories/inventory_repository.dart';
import 'package:rms/src/data/repositories/local_inventory_repository.dart';
import 'package:rms/src/domain/models/audit_entry.dart';
import 'package:rms/src/domain/models/inventory_item.dart';
import 'package:rms/src/domain/models/stock_movement.dart';

int _seq = 0;

Future<LocalDatabase> _memoryDb() => LocalDatabase.memory('rms_inv_${_seq++}');

InventoryItemModel _item(
  String id, {
  double onHand = 0,
  double reorderAt = 0,
  SyncStatus sync = SyncStatus.pendingSync,
}) =>
    InventoryItemModel(
      id: id,
      name: 'صنف $id',
      unit: 'كجم',
      onHand: onHand,
      reorderAt: reorderAt,
      syncStatus: sync,
    );

void main() {
  late LocalDatabase db;
  late AuditLog audit;
  late LocalInventoryRepository repo;

  setUp(() async {
    db = await _memoryDb();
    audit = AuditLog(db);
    repo = LocalInventoryRepository(
      db,
      outbox: OutboxStore(db),
      audit: audit,
      clock: () => DateTime(2026, 10, 13, 12),
    );
  });

  tearDown(() => db.close());

  test('records a movement, updates the balance and queues a command',
      () async {
    await repo.seedItems([_item('I1', onHand: 10)]);

    final updated = await repo.recordMovement(
      itemId: 'I1',
      delta: 5,
      reason: StockMovementReason.receipt,
      createdOffline: true,
    );

    expect(updated.onHand, 15);
    expect(updated.localRevision, 2);
    expect(updated.syncStatus, SyncStatus.pendingSync);

    final movements = await repo.listMovements();
    expect(movements, hasLength(1));
    expect(movements.single.delta, 5);
    expect(movements.single.baseRevision, 1);

    final outbox = await OutboxStore(db).all();
    expect(outbox.single.operationType, 'recordStockMovement');
    expect((await audit.list()).single.action, AuditAction.recordStockMovement);
  });

  test('the balance is always the sum of the ledger', () async {
    await repo.seedItems([_item('I1')]);

    await repo.recordMovement(itemId: 'I1', delta: 10, reason: StockMovementReason.receipt);
    await repo.recordMovement(itemId: 'I1', delta: -3, reason: StockMovementReason.sale);

    final item = (await repo.listItems()).single;
    final sum = (await repo.listMovements())
        .fold<double>(0, (total, movement) => total + movement.delta);
    expect(item.onHand, 7);
    expect(item.onHand, sum);
  });

  test('a count on the current revision is applied', () async {
    await repo.seedItems([_item('I1', onHand: 10)]);

    final outcome =
        await repo.adjustToCount(itemId: 'I1', counted: 8, baseRevision: 1);

    expect(outcome, StockCountOutcome.applied);
    expect((await repo.listItems()).single.onHand, 8);
    final movement = (await repo.listMovements()).single;
    expect(movement.reason, StockMovementReason.adjustment);
    expect(movement.delta, -2);
  });

  test('a stale count is flagged instead of overwriting a newer balance',
      () async {
    await repo.seedItems([_item('I1', onHand: 10, sync: SyncStatus.synced)]);
    // Another device moved the item first.
    await repo.recordMovement(itemId: 'I1', delta: 2, reason: StockMovementReason.receipt);

    final outcome =
        await repo.adjustToCount(itemId: 'I1', counted: 5, baseRevision: 1);

    expect(outcome, StockCountOutcome.conflict);
    final item = (await repo.listItems()).single;
    expect(item.onHand, 12);
    expect(item.syncStatus, SyncStatus.conflict);

    final conflicts = (await OutboxStore(db).all())
        .where((e) => e.syncStatus == OutboxStatus.conflict);
    expect(conflicts, hasLength(1));
    expect(conflicts.single.operationType, 'stockCountConflict');
    expect((await audit.list()).map((e) => e.action),
        contains(AuditAction.stockConflict));
  });

  test('acknowledgement marks the movement and its item synced', () async {
    await repo.seedItems([_item('I1')]);
    await repo.recordMovement(itemId: 'I1', delta: 4, reason: StockMovementReason.receipt);

    final entry = (await OutboxStore(db).all()).single;
    await repo.applySynced(entry);

    expect((await repo.listMovements()).single.syncStatus, SyncStatus.synced);
    expect((await repo.listItems()).single.syncStatus, SyncStatus.synced);
  });

  test('cacheItems replaces the cached items', () async {
    await repo.seedItems([_item('I1', onHand: 1)]);

    await repo.cacheItems([_item('I2', onHand: 9)]);

    final items = await repo.listItems();
    expect(items.map((i) => i.id), ['I2']);
    expect(items.single.onHand, 9);
  });
}

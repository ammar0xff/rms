import 'package:sembast/sembast.dart';
import 'package:uuid/uuid.dart';

import '../../core/config/app_version.dart';
import '../../core/logging/app_logger.dart';
import '../../domain/models/audit_entry.dart';
import '../../domain/models/inventory_item.dart';
import '../../domain/models/stock_movement.dart';
import '../local/audit_log.dart';
import '../local/local_database.dart';
import '../local/local_stores.dart';
import '../local/outbox/outbox_entry.dart';
import '../local/outbox/outbox_status.dart';
import '../sync/record_mirror.dart';
import '../local/outbox/outbox_store.dart';
import 'inventory_repository.dart';

/// Local-first stock ledger backed by the on-device store.
///
/// Relative movements are append-only and commute, so the ledger stays
/// consistent under concurrent offline edits; a physical count carries the
/// revision it was based on, and a stale count is flagged for review rather
/// than silently overwriting a newer balance.
class LocalInventoryRepository implements InventoryRepository {
  LocalInventoryRepository(
    this._db, {
    OutboxStore? outbox,
    AuditLog? audit,
    Uuid? uuid,
    DateTime Function()? clock,
    RecordMirror? mirror,
  })  : _outbox = outbox ?? OutboxStore(_db),
        _audit = audit ?? AuditLog(_db),
        _uuid = uuid ?? const Uuid(),
        _clock = clock ?? DateTime.now,
        _mirror = mirror;

  final LocalDatabase _db;
  final OutboxStore _outbox;
  final AuditLog _audit;
  final Uuid _uuid;
  final DateTime Function() _clock;

  /// Best-effort data mirror (see [RecordMirror]). Null outside Firebase
  /// mode, where there is nowhere to mirror to.
  final RecordMirror? _mirror;

  @override
  Future<List<InventoryItemModel>> listItems() async {
    final snapshots = await LocalStores.inventory.find(_db.db);
    final items =
        snapshots.map((s) => InventoryItemModel.fromRecord(s.value)).toList()
          ..sort((a, b) => a.name.compareTo(b.name));
    return items;
  }

  @override
  Future<List<StockMovementModel>> listMovements({String? itemId}) async {
    final snapshots = await LocalStores.stockMovements.find(
      _db.db,
      finder: itemId == null
          ? null
          : Finder(filter: Filter.equals('itemId', itemId)),
    );
    final movements =
        snapshots.map((s) => StockMovementModel.fromRecord(s.value)).toList()
          ..sort((a, b) => a.at.compareTo(b.at));
    return movements;
  }

  @override
  Future<InventoryItemModel> recordMovement({
    required String itemId,
    required double delta,
    required StockMovementReason reason,
    String? reference,
    bool createdOffline = false,
  }) async {
    if (delta == 0) {
      throw ArgumentError.value(
        delta,
        'delta',
        'Movement delta must be non-zero',
      );
    }
    InventoryItemModel? updated;
    await _db.transaction((txn) async {
      updated = await postMovement(
        txn,
        itemId: itemId,
        delta: delta,
        reason: reason,
        reference: reference,
        createdOffline: createdOffline,
      );
    });
    final result = updated;
    if (result == null) {
      throw StateError('inventory item $itemId not found');
    }
    return result;
  }

  /// Posts a movement using the caller's [txn].
  ///
  /// Exposed so composite operations (such as receiving a purchase order) can
  /// post several movements atomically inside one transaction, instead of
  /// nesting transactions.
  Future<InventoryItemModel> postMovement(
    Transaction txn, {
    required String itemId,
    required double delta,
    required StockMovementReason reason,
    String? reference,
    bool createdOffline = false,
  }) async {
    final now = _clock();
    final movementId = _uuid.v4();
    final record = LocalStores.inventory.record(itemId);
    final existing = await record.get(txn);
    if (existing == null) {
      throw StateError('inventory item $itemId not found');
    }
    final item = InventoryItemModel.fromRecord(existing);
    final baseRevision = item.localRevision;
    final movement = StockMovementModel(
      id: movementId,
      itemId: itemId,
      delta: delta,
      reason: reason,
      at: now,
      reference: reference,
      baseRevision: baseRevision,
      createdOffline: createdOffline,
    );
    item.onHand += delta;
    item.localRevision = baseRevision + 1;
    item.syncStatus = SyncStatus.pendingSync;
    await record.put(txn, item.toRecord());
    await LocalStores.stockMovements
        .record(movementId)
        .put(txn, movement.toRecord());
    await _outbox.append(
      txn,
      _entry(
        entityType: 'stockMovement',
        entityId: movementId,
        operationType: 'recordStockMovement',
        createdAt: now,
        payload: {
          'id': movementId,
          'itemId': itemId,
          'delta': delta,
          'reason': reason.name,
          'baseRevision': baseRevision,
        },
      ),
    );
    await _audit.append(
      txn,
      AuditEntry(
        id: _uuid.v4(),
        action: AuditAction.recordStockMovement,
        entityType: 'stockMovement',
        entityId: movementId,
        summary:
            '${delta > 0 ? '+' : ''}${delta.toStringAsFixed(2)} · ${item.name} · ${reason.label}',
        at: now,
        amount: delta,
        createdOffline: createdOffline,
      ),
    );
    AppLogger.info('Stock movement $movementId posted for $itemId ($delta).');
    return item;
  }

  @override
  Future<StockCountOutcome> adjustToCount({
    required String itemId,
    required double counted,
    int? baseRevision,
    bool createdOffline = false,
  }) async {
    final now = _clock();
    final movementId = _uuid.v4();
    var outcome = StockCountOutcome.applied;
    await _db.transaction((txn) async {
      final record = LocalStores.inventory.record(itemId);
      final existing = await record.get(txn);
      if (existing == null) return;
      final item = InventoryItemModel.fromRecord(existing);
      final priorRevision = item.localRevision;

      if (baseRevision != null && baseRevision != priorRevision) {
        // Another device moved this item since the counter looked. Keep the
        // newer balance and leave the count for explicit review.
        item.localRevision = priorRevision + 1;
        item.syncStatus = SyncStatus.conflict;
        await record.put(txn, item.toRecord());
        await _outbox.append(
          txn,
          _entry(
            entityType: 'inventoryItem',
            entityId: itemId,
            operationType: 'stockCountConflict',
            createdAt: now,
            status: OutboxStatus.conflict,
            payload: {
              'itemId': itemId,
              'counted': counted,
              'baseRevision': baseRevision,
              'currentRevision': priorRevision,
            },
          ),
        );
        await _audit.append(
          txn,
          AuditEntry(
            id: _uuid.v4(),
            action: AuditAction.stockConflict,
            entityType: 'inventoryItem',
            entityId: itemId,
            summary:
                'تعارض جرد · ${item.name} · أساس $baseRevision مقابل $priorRevision',
            at: now,
            createdOffline: true,
          ),
        );
        outcome = StockCountOutcome.conflict;
        return;
      }

      final delta = counted - item.onHand;
      if (delta == 0) {
        // Counted exactly what the ledger already said; nothing to sync.
        await _audit.append(
          txn,
          AuditEntry(
            id: _uuid.v4(),
            action: AuditAction.recordStockMovement,
            entityType: 'inventoryItem',
            entityId: itemId,
            summary: 'جرد مطابق · ${item.name} · ${counted.toStringAsFixed(2)}',
            at: now,
            createdOffline: createdOffline,
          ),
        );
        return;
      }

      final movement = StockMovementModel(
        id: movementId,
        itemId: itemId,
        delta: delta,
        reason: StockMovementReason.adjustment,
        at: now,
        reference: 'جرد فعلي',
        baseRevision: priorRevision,
        createdOffline: createdOffline,
      );
      item.onHand = counted;
      item.localRevision = priorRevision + 1;
      item.syncStatus = SyncStatus.pendingSync;
      await record.put(txn, item.toRecord());
      await LocalStores.stockMovements
          .record(movementId)
          .put(txn, movement.toRecord());
      await _outbox.append(
        txn,
        _entry(
          entityType: 'stockMovement',
          entityId: movementId,
          operationType: 'recordStockMovement',
          createdAt: now,
          payload: {
            'id': movementId,
            'itemId': itemId,
            'delta': delta,
            'reason': StockMovementReason.adjustment.name,
            'baseRevision': priorRevision,
          },
        ),
      );
      await _audit.append(
        txn,
        AuditEntry(
          id: _uuid.v4(),
          action: AuditAction.recordStockMovement,
          entityType: 'stockMovement',
          entityId: movementId,
          summary:
              'جرد ${counted.toStringAsFixed(2)} · ${item.name} · فرق ${delta.toStringAsFixed(2)}',
          at: now,
          amount: delta,
          createdOffline: createdOffline,
        ),
      );
      outcome = StockCountOutcome.applied;
    });
    return outcome;
  }

  @override
  Future<void> cacheItems(
    List<InventoryItemModel> items, {
    bool replace = true,
  }) async {
    if (items.isEmpty) return;
    await _db.transaction((txn) async {
      // A blind delete would destroy locally-created/edited rows carrying
      // pendingSync along with the deltas that reference them. Dirty rows
      // survive the replace; everything else is refreshed.
      final dirty = <String, Map<String, Object?>>{};
      if (replace) {
        final existing = await LocalStores.inventory.find(txn);
        for (final s in existing) {
          final item = InventoryItemModel.fromRecord(s.value);
          if (item.syncStatus != SyncStatus.synced) dirty[item.id] = s.value;
        }
        await LocalStores.inventory.delete(txn);
        for (final e in dirty.entries) {
          await LocalStores.inventory.record(e.key).put(txn, e.value);
        }
      }
      for (final item in items) {
        if (dirty.containsKey(item.id)) continue;
        await LocalStores.inventory.record(item.id).put(txn, item.toRecord());
      }
    });
  }

  /// Marks a movement, and its item (when fully drained), as synced.
  Future<void> applySynced(OutboxEntry entry) async {
    if (entry.entityType != 'stockMovement') return;
    final record = LocalStores.stockMovements.record(entry.entityId);
    final existing = await record.get(_db.db);
    if (existing == null) return;
    final movement = StockMovementModel.fromRecord(existing);
    movement.syncStatus = SyncStatus.synced;
    await record.put(_db.db, movement.toRecord());
    await _refreshItemSync(_db.db, movement.itemId);
    await mirrorRecord(_mirror, 
      entityType: 'stockMovement',
      entityId: entry.entityId,
      snapshot: movement.toRecord(),
    );
    final itemRecord = LocalStores.inventory.record(movement.itemId);
    final itemExisting = await itemRecord.get(_db.db);
    if (itemExisting != null) {
      await mirrorRecord(_mirror, 
        entityType: 'inventoryItem',
        entityId: movement.itemId,
        snapshot: itemExisting,
      );
    }
  }

  /// Marks an item synced once it has no movements still awaiting the backend.
  Future<void> _refreshItemSync(DatabaseClient client, String itemId) async {
    final record = LocalStores.inventory.record(itemId);
    final existing = await record.get(client);
    if (existing == null) return;
    final item = InventoryItemModel.fromRecord(existing);
    if (item.syncStatus == SyncStatus.conflict) return;
    final snapshots = await LocalStores.stockMovements.find(
      client,
      finder: Finder(filter: Filter.equals('itemId', itemId)),
    );
    final hasPending = snapshots.any(
      (s) => (s.value['syncStatus'] as String?) != SyncStatus.synced.name,
    );
    item.syncStatus =
        hasPending ? SyncStatus.pendingSync : SyncStatus.synced;
    await record.put(client, item.toRecord());
  }

  /// Writes pre-existing items without queueing commands (demo seeding).
  Future<void> seedItems(List<InventoryItemModel> items) async {
    if (items.isEmpty) return;
    await _db.transaction((txn) async {
      for (final item in items) {
        await LocalStores.inventory.record(item.id).put(txn, item.toRecord());
      }
    });
    AppLogger.info('Seeded ${items.length} demo inventory items.');
  }

  /// Writes pre-existing ledger lines without queueing commands (demo seeding).
  Future<void> seedMovements(List<StockMovementModel> movements) async {
    if (movements.isEmpty) return;
    await _db.transaction((txn) async {
      for (final movement in movements) {
        await LocalStores.stockMovements
            .record(movement.id)
            .put(txn, movement.toRecord());
      }
    });
    AppLogger.info('Seeded ${movements.length} demo stock movements.');
  }

  OutboxEntry _entry({
    required String entityType,
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

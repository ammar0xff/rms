import 'package:sembast/sembast.dart';
import 'package:uuid/uuid.dart';

import '../../core/config/app_version.dart';
import '../../core/logging/app_logger.dart';
import '../../domain/models/audit_entry.dart';
import '../../domain/models/stock_movement.dart';
import '../../domain/models/stock_transfer.dart';
import '../local/audit_log.dart';
import '../local/local_database.dart';
import '../local/local_stores.dart';
import '../local/outbox/outbox_entry.dart';
import '../local/outbox/outbox_status.dart';
import '../local/outbox/outbox_store.dart';
import '../sync/record_mirror.dart';
import 'inventory_repository.dart';
import 'transfer_repository.dart';

/// Local-first transfer ledger. The receipt leg posts a real inventory
/// movement through [InventoryRepository], so stock and transfer can never
/// disagree on this device.
class LocalTransferRepository implements TransferRepository {
  LocalTransferRepository(
    this._db, {
    required InventoryRepository inventory,
    OutboxStore? outbox,
    AuditLog? audit,
    Uuid? uuid,
    DateTime Function()? clock,
    RecordMirror? mirror,
  })  : _inventory = inventory,
        _outbox = outbox ?? OutboxStore(_db),
        _audit = audit ?? AuditLog(_db),
        _uuid = uuid ?? const Uuid(),
        _clock = clock ?? DateTime.now,
        _mirror = mirror;

  final LocalDatabase _db;
  final InventoryRepository _inventory;
  final OutboxStore _outbox;
  final AuditLog _audit;
  final Uuid _uuid;
  final DateTime Function() _clock;
  final RecordMirror? _mirror;

  @override
  Future<List<StockTransfer>> listTransfers() async {
    final snapshots = await LocalStores.transfers.find(_db.db);
    final transfers =
        snapshots.map((s) => StockTransfer.fromRecord(s.value)).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return transfers;
  }

  Future<StockTransfer> _get(Transaction? txn, String id) async {
    final db = txn ?? _db.db;
    final existing = await LocalStores.transfers.record(id).get(db);
    if (existing == null) throw StateError('transfer $id not found');
    return StockTransfer.fromRecord(existing);
  }

  Future<StockTransfer> _save(
    Transaction txn,
    StockTransfer transfer,
    String operationType,
    AuditAction action,
    String summary,
    DateTime now,
  ) async {
    transfer.syncStatus = SyncStatus.pendingSync;
    await LocalStores.transfers
        .record(transfer.id)
        .put(txn, transfer.toRecord());
    await _outbox.append(
      txn,
      OutboxEntry(
        operationId: _uuid.v4(),
        entityType: 'transfer',
        entityId: transfer.id,
        operationType: operationType,
        payload: transfer.toRecord(),
        schemaVersion: AppVersion.localSchemaVersion,
        idempotencyKey: _uuid.v4(),
        createdAt: now,
      ),
    );
    await _audit.append(
      txn,
      AuditEntry(
        id: _uuid.v4(),
        action: action,
        entityType: 'transfer',
        entityId: transfer.id,
        summary: summary,
        at: now,
      ),
    );
    return transfer;
  }

  Future<void> _mirrorTransfer(StockTransfer transfer) => mirrorRecord(
        _mirror,
        entityType: 'transfer',
        entityId: transfer.id,
        snapshot: transfer.toRecord(),
      );

  @override
  Future<StockTransfer> requestTransfer({
    required String itemId,
    required String itemName,
    required double quantity,
    required String unit,
    required String fromBranchId,
    required String fromBranchName,
    required String toBranchId,
    required String toBranchName,
    String courier = '',
    String? note,
  }) async {
    if (quantity <= 0) {
      throw ArgumentError.value(quantity, 'quantity', 'must be positive');
    }
    final now = _clock();
    final transfer = StockTransfer(
      id: _uuid.v4(),
      itemId: itemId,
      itemName: itemName,
      quantity: quantity,
      unit: unit,
      fromBranchId: fromBranchId,
      fromBranchName: fromBranchName,
      toBranchId: toBranchId,
      toBranchName: toBranchName,
      courier: courier,
      note: note,
      createdAt: now,
    );
    await _db.transaction((txn) async {
      await _save(txn, transfer, 'requestTransfer',
          AuditAction.requestTransfer, 'طلب تحويل $itemName × $quantity من $fromBranchName', now);
    });
    await _mirrorTransfer(transfer);
    AppLogger.info('Transfer ${transfer.id} requested.');
    return transfer;
  }

  @override
  Future<StockTransfer> advanceTransfer(String id) async {
    const next = {
      TransferStatus.requested: TransferStatus.approved,
      TransferStatus.approved: TransferStatus.inTransit,
    };
    final now = _clock();
    StockTransfer? done;
    await _db.transaction((txn) async {
      final transfer = await _get(txn, id);
      final following = next[transfer.status];
      if (following == null) {
        throw StateError('transfer $id cannot advance from ${transfer.status.name}');
      }
      transfer.status = following;
      transfer.decidedAt = now;
      done = await _save(txn, transfer, 'advanceTransfer',
          AuditAction.requestTransfer, 'تحويل $id → ${following.label}', now);
    });
    await _mirrorTransfer(done!);
    return done!;
  }

  @override
  Future<StockTransfer> cancelTransfer(String id) async {
    final now = _clock();
    StockTransfer? done;
    await _db.transaction((txn) async {
      final transfer = await _get(txn, id);
      if (!transfer.status.isOpen) {
        throw StateError('transfer $id is already closed');
      }
      transfer.status = TransferStatus.cancelled;
      transfer.decidedAt = now;
      done = await _save(txn, transfer, 'cancelTransfer',
          AuditAction.requestTransfer, 'إلغاء تحويل $id', now);
    });
    await _mirrorTransfer(done!);
    return done!;
  }

  @override
  Future<StockTransfer> receiveTransfer(String id) async {
    final now = _clock();
    StockTransfer? done;
    await _db.transaction((txn) async {
      final transfer = await _get(txn, id);
      if (transfer.status == TransferStatus.received) {
        // Idempotent: the stock was already posted.
        done = transfer;
        return;
      }
      if (transfer.status != TransferStatus.inTransit) {
        throw StateError(
            'transfer $id must be in transit before receiving');
      }
      transfer.status = TransferStatus.received;
      transfer.decidedAt = now;
      done = await _save(txn, transfer, 'receiveTransfer',
          AuditAction.receiveTransfer,
          'استلام تحويل ${transfer.itemName} × ${transfer.quantity}', now);
    });
    // The stock leg posts outside the transfer transaction through the
    // inventory repo, which owns balance math. Receiving twice is safe:
    // the status gate above runs first.
    await _inventory.recordMovement(
      itemId: done!.itemId,
      delta: done!.quantity,
      reason: StockMovementReason.transfer,
      reference: 'تحويل ${done!.id}',
      createdOffline: true,
    );
    await _mirrorTransfer(done!);
    AppLogger.info('Transfer $id received (+${done!.quantity}).');
    return done!;
  }

  @override
  Future<void> applySynced(OutboxEntry entry) async {
    if (entry.entityType != 'transfer') return;
    final record = LocalStores.transfers.record(entry.entityId);
    final existing = await record.get(_db.db);
    if (existing == null) return;
    final transfer = StockTransfer.fromRecord(existing);
    if (!await _outbox.hasOutstandingFor(
        entityType: 'transfer', entityId: entry.entityId)) {
      transfer.syncStatus = SyncStatus.synced;
    }
    await record.put(_db.db, transfer.toRecord());
    await _mirrorTransfer(transfer);
  }
}

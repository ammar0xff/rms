import 'package:sembast/sembast.dart';
import 'package:uuid/uuid.dart';

import '../../core/config/app_version.dart';
import '../../core/logging/app_logger.dart';
import '../../domain/models/audit_entry.dart';
import '../../domain/models/purchase_order.dart';
import '../../domain/models/stock_movement.dart';
import '../../domain/models/supplier.dart';
import '../local/audit_log.dart';
import '../local/local_database.dart';
import '../local/local_stores.dart';
import '../local/outbox/outbox_entry.dart';
import '../local/outbox/outbox_status.dart';
import '../local/outbox/outbox_store.dart';
import 'local_inventory_repository.dart';
import 'purchase_repository.dart';

/// Local-first purchasing backed by the on-device store.
///
/// Receiving an order posts its lines to the stock ledger in the **same**
/// transaction that marks the order received, so stock and the order can never
/// drift apart, and a retried receive is a no-op.
class LocalPurchaseRepository implements PurchaseRepository {
  LocalPurchaseRepository(
    this._db, {
    required LocalInventoryRepository inventory,
    OutboxStore? outbox,
    AuditLog? audit,
    Uuid? uuid,
    DateTime Function()? clock,
  })  : _inventory = inventory,
        _outbox = outbox ?? OutboxStore(_db),
        _audit = audit,
        _uuid = uuid ?? const Uuid(),
        _clock = clock ?? DateTime.now;

  final LocalDatabase _db;
  final LocalInventoryRepository _inventory;
  final OutboxStore _outbox;
  final AuditLog? _audit;
  final Uuid _uuid;
  final DateTime Function() _clock;

  @override
  Future<List<PurchaseOrderModel>> listPurchases() async {
    final snapshots = await LocalStores.purchases.find(_db.db);
    final purchases =
        snapshots.map((s) => PurchaseOrderModel.fromRecord(s.value)).toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return purchases;
  }

  @override
  Future<PurchaseOrderModel> createPurchase({
    required String supplierId,
    required String supplierName,
    required String reference,
    required List<PurchaseOrderLine> lines,
    bool createdOffline = false,
  }) async {
    if (lines.isEmpty) {
      throw ArgumentError.value(
        lines,
        'lines',
        'A purchase order needs at least one line',
      );
    }
    final now = _clock();
    final id = _uuid.v4();
    final purchase = PurchaseOrderModel(
      id: id,
      supplierId: supplierId,
      supplierName: supplierName,
      reference: reference,
      lines: List.unmodifiable(lines),
      createdAt: now,
      createdOffline: createdOffline,
    );
    await _db.transaction((txn) async {
      await LocalStores.purchases.record(id).put(txn, purchase.toRecord());
      await _outbox.append(
        txn,
        _entry(
          entityType: 'purchase',
          entityId: id,
          operationType: 'createPurchase',
          createdAt: now,
          payload: {
            'id': id,
            'supplierId': supplierId,
            'reference': reference,
            'lineCount': lines.length,
            'total': purchase.total,
          },
        ),
      );
      await _audit?.append(
        txn,
        AuditEntry(
          id: _uuid.v4(),
          action: AuditAction.createPurchase,
          entityType: 'purchase',
          entityId: id,
          summary: 'أمر شراء $reference · $supplierName',
          at: now,
          amount: purchase.total,
          createdOffline: createdOffline,
        ),
      );
    });
    AppLogger.info('Purchase order $reference created ($id).');
    return purchase;
  }

  @override
  Future<PurchaseReceiveOutcome> receivePurchase(
    String id, {
    bool createdOffline = false,
  }) async {
    var outcome = PurchaseReceiveOutcome.notFound;
    await _db.transaction((txn) async {
      final record = LocalStores.purchases.record(id);
      final existing = await record.get(txn);
      if (existing == null) {
        outcome = PurchaseReceiveOutcome.notFound;
        return;
      }
      final purchase = PurchaseOrderModel.fromRecord(existing);
      if (purchase.isReceived) {
        outcome = PurchaseReceiveOutcome.alreadyReceived;
        return;
      }
      final now = _clock();
      for (final line in purchase.lines) {
        await _inventory.postMovement(
          txn,
          itemId: line.itemId,
          delta: line.quantity,
          reason: StockMovementReason.receipt,
          reference: purchase.reference,
          createdOffline: createdOffline,
        );
      }
      purchase.status = PurchaseOrderStatus.received;
      purchase.receivedAt = now;
      purchase.localRevision = purchase.localRevision + 1;
      purchase.syncStatus = SyncStatus.pendingSync;
      // Receiving the goods is what creates the debt, so the order total is
      // added to the supplier's payable in the same transaction as the stock
      // post: stock and payables can never drift apart.
      final supplierRecord = LocalStores.suppliers.record(purchase.supplierId);
      final existingSupplier = await supplierRecord.get(txn);
      if (existingSupplier != null) {
        final supplier = SupplierModel.fromRecord(existingSupplier);
        supplier.payable = supplier.payable + purchase.total;
        supplier.localRevision = supplier.localRevision + 1;
        supplier.syncStatus = SyncStatus.pendingSync;
        await supplierRecord.put(txn, supplier.toRecord());
      }
      await record.put(txn, purchase.toRecord());
      await _outbox.append(
        txn,
        _entry(
          entityType: 'purchase',
          entityId: id,
          operationType: 'receivePurchase',
          createdAt: now,
          payload: {
            'id': id,
            'reference': purchase.reference,
            'total': purchase.total,
          },
        ),
      );
      await _audit?.append(
        txn,
        AuditEntry(
          id: _uuid.v4(),
          action: AuditAction.receivePurchase,
          entityType: 'purchase',
          entityId: id,
          summary: 'استلام ${purchase.reference} · ${purchase.supplierName}',
          at: now,
          amount: purchase.total,
          createdOffline: createdOffline,
        ),
      );
      outcome = PurchaseReceiveOutcome.received;
    });
    return outcome;
  }

  @override
  Future<PurchaseCancelOutcome> cancelPurchase(
    String id, {
    bool createdOffline = false,
  }) async {
    var outcome = PurchaseCancelOutcome.notFound;
    await _db.transaction((txn) async {
      final record = LocalStores.purchases.record(id);
      final existing = await record.get(txn);
      if (existing == null) {
        outcome = PurchaseCancelOutcome.notFound;
        return;
      }
      final purchase = PurchaseOrderModel.fromRecord(existing);
      if (purchase.isReceived) {
        outcome = PurchaseCancelOutcome.alreadyReceived;
        return;
      }
      if (purchase.isCancelled) {
        outcome = PurchaseCancelOutcome.alreadyCancelled;
        return;
      }
      final now = _clock();
      // Nothing is posted to the stock ledger: an open order has never moved
      // stock, so cancelling it only closes the intent locally.
      purchase.status = PurchaseOrderStatus.cancelled;
      purchase.localRevision = purchase.localRevision + 1;
      purchase.syncStatus = SyncStatus.pendingSync;
      await record.put(txn, purchase.toRecord());
      await _outbox.append(
        txn,
        _entry(
          entityType: 'purchase',
          entityId: id,
          operationType: 'cancelPurchase',
          createdAt: now,
          payload: {
            'id': id,
            'reference': purchase.reference,
          },
        ),
      );
      await _audit?.append(
        txn,
        AuditEntry(
          id: _uuid.v4(),
          action: AuditAction.cancelPurchase,
          entityType: 'purchase',
          entityId: id,
          summary: 'إلغاء ${purchase.reference} · ${purchase.supplierName}',
          at: now,
          amount: purchase.total,
          createdOffline: createdOffline,
        ),
      );
      outcome = PurchaseCancelOutcome.cancelled;
    });
    return outcome;
  }

  /// Marks a purchase order synced once the backend acknowledges it.
  Future<void> applySynced(OutboxEntry entry) async {
    if (entry.entityType != 'purchase') return;
    final record = LocalStores.purchases.record(entry.entityId);
    final existing = await record.get(_db.db);
    if (existing == null) return;
    final purchase = PurchaseOrderModel.fromRecord(existing);
    purchase.syncStatus = SyncStatus.synced;
    await record.put(_db.db, purchase.toRecord());
  }

  /// Writes pre-existing purchase orders without queueing commands (seeding).
  Future<void> seedPurchases(List<PurchaseOrderModel> purchases) async {
    if (purchases.isEmpty) return;
    await _db.transaction((txn) async {
      for (final purchase in purchases) {
        await LocalStores.purchases
            .record(purchase.id)
            .put(txn, purchase.toRecord());
      }
    });
    AppLogger.info('Seeded ${purchases.length} demo purchase orders.');
  }

  OutboxEntry _entry({
    required String entityType,
    required String entityId,
    required String operationType,
    required DateTime createdAt,
    required Map<String, Object?> payload,
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
      );
}

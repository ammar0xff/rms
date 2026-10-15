import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/data/local/local_database.dart';
import 'package:rms/src/data/local/outbox/outbox_entry.dart';
import 'package:rms/src/data/local/outbox/outbox_status.dart';
import 'package:rms/src/data/local/outbox/outbox_store.dart';
import 'package:rms/src/data/repositories/local_inventory_repository.dart';
import 'package:rms/src/domain/models/inventory_item.dart';
import 'package:rms/src/data/repositories/local_purchase_repository.dart';
import 'package:rms/src/data/repositories/local_supplier_repository.dart';
import 'package:rms/src/domain/models/purchase_order.dart';
import 'package:rms/src/domain/models/supplier.dart';

int _seq = 0;

Future<LocalDatabase> _memoryDb() => LocalDatabase.memory('rms_pay_${_seq++}');

OutboxEntry _purchaseAck(String purchaseId, String supplierId) => OutboxEntry(
      operationId: 'op-ack',
      entityType: 'purchase',
      entityId: purchaseId,
      operationType: 'receivePurchase',
      payload: {'supplierId': supplierId},
      schemaVersion: 1,
      idempotencyKey: 'idem-ack',
      createdAt: DateTime(2026, 10, 13),
      syncStatus: OutboxStatus.synced,
    );

void main() {
  late LocalDatabase db;
  late LocalPurchaseRepository purchases;
  late LocalSupplierRepository suppliers;

  setUp(() async {
    db = await _memoryDb();
    final inventory = LocalInventoryRepository(db);
    purchases = LocalPurchaseRepository(
      db,
      inventory: inventory,
    );
    suppliers = LocalSupplierRepository(db);
    await inventory.seedItems([
      InventoryItemModel(
        id: 'i-1',
        name: 'صنف',
        unit: 'قطعة',
        onHand: 0,
        reorderAt: 5,
      ),
    ]);
    await suppliers.seedSuppliers([
      SupplierModel(id: 's-1', name: 'مورد', payable: 100),
    ]);
  });

  tearDown(() => db.close());

  group('receive-then-ack payable bookkeeping', () {
    test('the receive command carries the resulting payable', () async {
      final order = await purchases.createPurchase(
        supplierId: 's-1',
        supplierName: 'مورد',
        reference: 'PO-1',
        lines: const [
          PurchaseOrderLine(itemId: 'i-1', name: 'صنف', quantity: 2, unitCost: 25),
        ],
      );

      await purchases.receivePurchase(order.id);

      final queued = await OutboxStore(db).all();
      final receive = queued.firstWhere(
        (e) => e.operationType == 'receivePurchase',
      );
      // The receipt is what creates the debt: the server gets the payable it
      // produces, not just a total it cannot attribute.
      expect(receive.payload['supplierId'], 's-1');
      expect(receive.payload['supplierPayable'], 150);
      expect(receive.payload['total'], 50);
    });

    test('acking the receipt clears the dirty supplier flag when quiet',
        () async {
      final order = await purchases.createPurchase(
        supplierId: 's-1',
        supplierName: 'مورد',
        reference: 'PO-1',
        lines: const [
          PurchaseOrderLine(itemId: 'i-1', name: 'صنف', quantity: 2, unitCost: 25),
        ],
      );
      await purchases.receivePurchase(order.id);

      var supplier =
          (await suppliers.listSuppliers()).singleWhere((s) => s.id == 's-1');
      expect(supplier.syncStatus, SyncStatus.pendingSync);

      // No supplier command was ever queued, so no supplier ack will come.
      // The purchase ack clears the flag once nothing is outstanding.
      await purchases.applySynced(_purchaseAck(order.id, 's-1'));

      supplier =
          (await suppliers.listSuppliers()).singleWhere((s) => s.id == 's-1');
      expect(supplier.syncStatus, SyncStatus.synced);
      expect(supplier.payable, 150);
    });
  });
}

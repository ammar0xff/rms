import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/data/local/audit_log.dart';
import 'package:rms/src/data/local/local_database.dart';
import 'package:rms/src/data/local/outbox/outbox_status.dart';
import 'package:rms/src/data/local/outbox/outbox_store.dart';
import 'package:rms/src/data/repositories/local_inventory_repository.dart';
import 'package:rms/src/data/repositories/local_purchase_repository.dart';
import 'package:rms/src/data/repositories/local_supplier_repository.dart';
import 'package:rms/src/data/repositories/purchase_repository.dart';
import 'package:rms/src/data/repositories/supplier_repository.dart';
import 'package:rms/src/domain/models/audit_entry.dart';
import 'package:rms/src/domain/models/inventory_item.dart';
import 'package:rms/src/domain/models/purchase_order.dart';
import 'package:rms/src/domain/models/stock_movement.dart';

int _seq = 0;

Future<LocalDatabase> _memoryDb() => LocalDatabase.memory('rms_purch_${_seq++}');

InventoryItemModel _item(String id, {double onHand = 0}) => InventoryItemModel(
      id: id,
      name: 'صنف $id',
      unit: 'كجم',
      onHand: onHand,
      reorderAt: 0,
    );

void main() {
  late LocalDatabase db;
  late AuditLog audit;
  late LocalInventoryRepository inventory;
  late LocalPurchaseRepository purchases;
  late LocalSupplierRepository suppliers;

  setUp(() async {
    db = await _memoryDb();
    audit = AuditLog(db);
    final outbox = OutboxStore(db);
    final clock = () => DateTime(2026, 10, 13, 15);
    inventory = LocalInventoryRepository(
      db,
      outbox: outbox,
      audit: audit,
      clock: clock,
    );
    purchases = LocalPurchaseRepository(
      db,
      inventory: inventory,
      outbox: outbox,
      audit: audit,
      clock: clock,
    );
    suppliers = LocalSupplierRepository(
      db,
      outbox: outbox,
      audit: audit,
      clock: clock,
    );
  });

  tearDown(() => db.close());

  test('creates a supplier and queues its sync command', () async {
    await suppliers.createSupplier(
      name: 'مطاحن الشمال',
      phone: '0100',
      category: 'حبوب',
      createdOffline: true,
    );

    expect((await suppliers.listSuppliers()).single.name, 'مطاحن الشمال');
    final entry = (await OutboxStore(db).all()).single;
    expect(entry.operationType, 'saveSupplier');
    expect(entry.entityType, 'supplier');
    expect((await audit.list()).single.action, AuditAction.saveSupplier);
  });

  test('creates a purchase order with its lines', () async {
    await inventory.seedItems([_item('I1', onHand: 5)]);

    final purchase = await purchases.createPurchase(
      supplierId: 'SP-1',
      supplierName: 'مورد',
      reference: 'PO-1',
      lines: const [
        PurchaseOrderLine(
          itemId: 'I1',
          name: 'صنف I1',
          quantity: 3.0,
          unitCost: 10.0,
        ),
      ],
      createdOffline: true,
    );

    expect(purchase.isOpen, isTrue);
    expect(purchase.total, 30);
    final listed = (await purchases.listPurchases()).single;
    expect(listed.lines.single.quantity, 3.0);
    expect((await OutboxStore(db).all()).single.operationType, 'createPurchase');
    expect(
      (await audit.list()).map((e) => e.action),
      contains(AuditAction.createPurchase),
    );
  });

  test('receiving posts one movement per line and is idempotent', () async {
    await inventory.seedItems([_item('I1', onHand: 5), _item('I2')]);
    final purchase = await purchases.createPurchase(
      supplierId: 'SP-1',
      supplierName: 'مورد',
      reference: 'PO-2',
      lines: const [
        PurchaseOrderLine(
          itemId: 'I1',
          name: 'أ',
          quantity: 3.0,
          unitCost: 10.0,
        ),
        PurchaseOrderLine(
          itemId: 'I2',
          name: 'ب',
          quantity: 2.0,
          unitCost: 5.0,
        ),
      ],
    );

    final first = await purchases.receivePurchase(purchase.id, createdOffline: true);
    expect(first, PurchaseReceiveOutcome.received);

    final items = {for (final i in await inventory.listItems()) i.id: i};
    expect(items['I1']!.onHand, 8);
    expect(items['I2']!.onHand, 2);
    expect(
      (await inventory.listMovements())
          .where((m) => m.reason == StockMovementReason.receipt)
          .length,
      2,
    );
    expect((await purchases.listPurchases()).single.isReceived, isTrue);

    // A retried receive must be a no-op: no extra movements or commands.
    final outboxBefore = (await OutboxStore(db).all()).length;
    final second = await purchases.receivePurchase(purchase.id);
    expect(second, PurchaseReceiveOutcome.alreadyReceived);
    expect((await OutboxStore(db).all()).length, outboxBefore);
    final after = {for (final i in await inventory.listItems()) i.id: i};
    expect(after['I1']!.onHand, 8);
    expect(after['I2']!.onHand, 2);
  });

  test('receiving an unknown order reports notFound', () async {
    expect(
      await purchases.receivePurchase('missing'),
      PurchaseReceiveOutcome.notFound,
    );
  });

  test('receiving rolls back atomically when a line item is missing', () async {
    await inventory.seedItems([_item('I1')]);
    final purchase = await purchases.createPurchase(
      supplierId: 'SP-1',
      supplierName: 'مورد',
      reference: 'PO-3',
      lines: const [
        PurchaseOrderLine(
          itemId: 'I1',
          name: 'أ',
          quantity: 2.0,
          unitCost: 1.0,
        ),
        PurchaseOrderLine(
          itemId: 'GHOST',
          name: 'شبح',
          quantity: 1.0,
          unitCost: 1.0,
        ),
      ],
    );

    await expectLater(
      purchases.receivePurchase(purchase.id),
      throwsA(isA<StateError>()),
    );

    expect((await purchases.listPurchases()).single.isOpen, isTrue);
    expect((await inventory.listItems()).single.onHand, 0);
    expect(
      (await inventory.listMovements())
          .where((m) => m.reason == StockMovementReason.receipt),
      isEmpty,
    );
  });

  test('acknowledgement marks the order and supplier synced', () async {
    await inventory.seedItems([_item('I1')]);
    await suppliers.createSupplier(name: 'مورد');
    await purchases.createPurchase(
      supplierId: 'SP-1',
      supplierName: 'مورد',
      reference: 'PO-4',
      lines: const [
        PurchaseOrderLine(
          itemId: 'I1',
          name: 'أ',
          quantity: 1.0,
          unitCost: 2.0,
        ),
      ],
    );

    final entries = await OutboxStore(db).all();
    // Engine order: entries are marked synced before fold-back, so
    // a quiet-guard refusal here would mean genuinely outstanding
    // work, not test scaffolding.
    for (final e in await OutboxStore(db).all()) {
      await OutboxStore(db).markSynced(e.operationId);
    }
    await suppliers.applySynced(
      entries.firstWhere((e) => e.entityType == 'supplier'),
    );
    await purchases.applySynced(
      entries.firstWhere((e) => e.entityType == 'purchase'),
    );

    expect((await suppliers.listSuppliers()).single.syncStatus, SyncStatus.synced);
    expect((await purchases.listPurchases()).single.syncStatus, SyncStatus.synced);
  });

  test('receiving increases the supplier payable', () async {
    await inventory.seedItems([_item('I1')]);
    final supplier = await suppliers.createSupplier(name: 'مورد', payable: 100);
    final purchase = await purchases.createPurchase(
      supplierId: supplier.id,
      supplierName: supplier.name,
      reference: 'PO-PAY',
      lines: const [
        PurchaseOrderLine(
          itemId: 'I1',
          name: 'أ',
          quantity: 3.0,
          unitCost: 10.0,
        ),
      ],
    );

    await purchases.receivePurchase(purchase.id, createdOffline: true);

    final updated = (await suppliers.listSuppliers()).single;
    expect(updated.payable, 130);
    expect(updated.syncStatus, SyncStatus.pendingSync);
  });

  test('cancelling an open order is idempotent and audited', () async {
    await inventory.seedItems([_item('I1')]);
    final purchase = await purchases.createPurchase(
      supplierId: 'SP-1',
      supplierName: 'مورد',
      reference: 'PO-CANCEL',
      lines: const [
        PurchaseOrderLine(
          itemId: 'I1',
          name: 'أ',
          quantity: 1.0,
          unitCost: 5.0,
        ),
      ],
    );

    final first =
        await purchases.cancelPurchase(purchase.id, createdOffline: true);
    expect(first, PurchaseCancelOutcome.cancelled);
    expect((await purchases.listPurchases()).single.isCancelled, isTrue);
    expect(
      (await audit.list()).map((e) => e.action),
      contains(AuditAction.cancelPurchase),
    );

    // A retried cancel must be a no-op: no extra commands or audits.
    final outboxBefore = (await OutboxStore(db).all()).length;
    final auditBefore = (await audit.list()).length;
    final second = await purchases.cancelPurchase(purchase.id);
    expect(second, PurchaseCancelOutcome.alreadyCancelled);
    expect((await OutboxStore(db).all()).length, outboxBefore);
    expect((await audit.list()).length, auditBefore);
  });

  test('cannot cancel a received order', () async {
    await inventory.seedItems([_item('I1')]);
    final purchase = await purchases.createPurchase(
      supplierId: 'SP-1',
      supplierName: 'مورد',
      reference: 'PO-RECV',
      lines: const [
        PurchaseOrderLine(
          itemId: 'I1',
          name: 'أ',
          quantity: 1.0,
          unitCost: 5.0,
        ),
      ],
    );
    await purchases.receivePurchase(purchase.id);

    expect(
      await purchases.cancelPurchase(purchase.id),
      PurchaseCancelOutcome.alreadyReceived,
    );
    expect((await purchases.listPurchases()).single.isReceived, isTrue);
  });

  test('cancelling an unknown order reports notFound', () async {
    expect(
      await purchases.cancelPurchase('missing'),
      PurchaseCancelOutcome.notFound,
    );
  });

  test('supplier payment reduces the payable and queues a command', () async {
    final supplier = await suppliers.createSupplier(name: 'مورد', payable: 500);

    final outcome = await suppliers.recordSupplierPayment(
      supplierId: supplier.id,
      amount: 200,
      reference: 'PAY-1',
      createdOffline: true,
    );

    expect(outcome, SupplierPaymentOutcome.recorded);
    final updated = (await suppliers.listSuppliers()).single;
    expect(updated.payable, 300);
    expect(updated.syncStatus, SyncStatus.pendingSync);
    final entry = (await OutboxStore(db).all())
        .firstWhere((e) => e.operationType == 'paySupplier');
    expect(entry.entityType, 'supplier');
    expect(
      (await audit.list()).map((e) => e.action),
      contains(AuditAction.paySupplier),
    );
  });

  test('supplier payment rejects invalid and over-payments', () async {
    final supplier = await suppliers.createSupplier(name: 'مورد', payable: 100);

    expect(
      await suppliers.recordSupplierPayment(
        supplierId: supplier.id,
        amount: 0,
        reference: 'PAY-0',
      ),
      SupplierPaymentOutcome.invalidAmount,
    );
    expect(
      await suppliers.recordSupplierPayment(
        supplierId: supplier.id,
        amount: 150,
        reference: 'PAY-2',
      ),
      SupplierPaymentOutcome.exceedsPayable,
    );
    expect(
      await suppliers.recordSupplierPayment(
        supplierId: 'missing',
        amount: 10,
        reference: 'PAY-3',
      ),
      SupplierPaymentOutcome.notFound,
    );
    expect((await suppliers.listSuppliers()).single.payable, 100);
  });
}

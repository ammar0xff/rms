import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/data/local/audit_log.dart';
import 'package:rms/src/data/local/local_database.dart';
import 'package:rms/src/data/local/outbox/outbox_status.dart';
import 'package:rms/src/data/local/outbox/outbox_store.dart';
import 'package:rms/src/data/repositories/local_cash_session_repository.dart';
import 'package:rms/src/data/repositories/local_delivery_repository.dart';
import 'package:rms/src/data/repositories/local_inventory_repository.dart';
import 'package:rms/src/data/repositories/local_order_repository.dart';
import 'package:rms/src/data/repositories/local_payment_repository.dart';
import 'package:rms/src/data/repositories/local_purchase_repository.dart';
import 'package:rms/src/data/repositories/local_reports_repository.dart';
import 'package:rms/src/data/repositories/local_supplier_repository.dart';
import 'package:rms/src/domain/models/cash_session.dart';
import 'package:rms/src/domain/models/collection.dart';
import 'package:rms/src/domain/models/inventory_item.dart';
import 'package:rms/src/domain/models/order.dart';
import 'package:rms/src/domain/models/order_draft.dart';
import 'package:rms/src/domain/models/payment.dart';
import 'package:rms/src/domain/models/purchase_order.dart';
import 'package:rms/src/domain/models/stock_movement.dart';

int _seq = 0;

final _now = DateTime(2026, 10, 13, 15);

void main() {
  late LocalDatabase db;
  late OutboxStore outbox;
  late AuditLog audit;
  late LocalOrderRepository orders;
  late LocalPaymentRepository payments;
  late LocalDeliveryRepository deliveries;
  late LocalCashSessionRepository cashSessions;
  late LocalInventoryRepository inventory;
  late LocalSupplierRepository suppliers;
  late LocalPurchaseRepository purchases;
  late LocalReportsRepository reports;

  setUp(() async {
    db = await LocalDatabase.memory('rms_reports_${_seq++}');
    outbox = OutboxStore(db);
    audit = AuditLog(db);
    final clock = () => _now;
    orders = LocalOrderRepository(db, outbox: outbox, clock: clock);
    payments = LocalPaymentRepository(
      db,
      outbox: outbox,
      audit: audit,
      clock: clock,
    );
    deliveries = LocalDeliveryRepository(
      db,
      outbox: outbox,
      audit: audit,
      clock: clock,
    );
    cashSessions = LocalCashSessionRepository(
      db,
      outbox: outbox,
      audit: audit,
      clock: clock,
    );
    inventory = LocalInventoryRepository(
      db,
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
    purchases = LocalPurchaseRepository(
      db,
      inventory: inventory,
      outbox: outbox,
      audit: audit,
      clock: clock,
    );
    reports = LocalReportsRepository(
      orders,
      payments,
      deliveries,
      cashSessions,
      inventory,
      purchases,
      suppliers,
      audit: audit,
      outbox: outbox,
    );
  });

  tearDown(() => db.close());

  test('builds a snapshot from the seeded local stores', () async {
    await orders.createOrder(
      OrderDraft(
        items: [
          OrderItem(productId: 'p', name: 'صنف', unitPrice: 30, quantity: 2),
        ],
        createdOffline: true,
      ),
    );
    await payments.recordPayment(
      const PaymentDraft(
        orderLocalId: 'o',
        orderRef: 'O',
        amount: 60,
        method: PaymentMethod.cash,
        createdOffline: true,
      ),
    );
    await inventory.seedItems([
      InventoryItemModel(
        id: 'I1',
        name: 'صنف',
        unit: 'كجم',
        onHand: 5,
        reorderAt: 10,
        syncStatus: SyncStatus.synced,
      ),
    ]);
    await inventory.seedMovements([
      StockMovementModel(
        id: 'm1',
        itemId: 'I1',
        delta: 5,
        reason: StockMovementReason.opening,
        at: _now,
        syncStatus: SyncStatus.synced,
      ),
    ]);
    await suppliers.createSupplier(name: 'مورد', payable: 100, createdOffline: true);
    await purchases.createPurchase(
      supplierId: 'S',
      supplierName: 'مورد',
      reference: 'PO-1',
      lines: const [
        PurchaseOrderLine(itemId: 'I1', name: 'صنف', quantity: 2, unitCost: 10),
      ],
      createdOffline: true,
    );
    await deliveries.seedCollections([
      CollectionModel(
        id: 'c1',
        deliveryId: 'd1',
        orderRef: 'O',
        driver: 'dr',
        amount: 18,
        method: PaymentMethod.cash,
        collectedAt: _now,
        syncStatus: SyncStatus.synced,
      ),
    ]);
    await cashSessions.seedSessions([
      CashSession(
        id: 'cs1',
        openedAt: _now.subtract(const Duration(hours: 3)),
        openingFloat: 200,
        status: CashSessionStatus.closed,
        expectedCash: 500,
        countedCash: 480,
        closedAt: _now,
        syncStatus: SyncStatus.synced,
      ),
    ]);

    final snapshot = await reports.load(now: _now);

    expect(snapshot.sales.orders, 1);
    expect(snapshot.sales.total, 60);
    expect(snapshot.payments.cash, 60);
    expect(snapshot.payments.collections, 18);
    expect(snapshot.inventory.onHandUnits, 5);
    expect(snapshot.inventory.lowCount, 1);
    expect(snapshot.purchasing.payables, 100);
    expect(snapshot.purchasing.openOrders, 1);
    expect(snapshot.purchasing.openValue, 20);
    expect(snapshot.cash.variance, -20);
    // Unacknowledged offline work is what makes the report "stale".
    expect(snapshot.pendingOperations, greaterThan(0));
    expect(snapshot.isStale, isTrue);
    expect(snapshot.recentAudit, isNotEmpty);
  });

  test('stays consistent after a concurrent offline movement', () async {
    await inventory.seedItems([
      InventoryItemModel(
        id: 'I1',
        name: 'صنف',
        unit: 'كجم',
        onHand: 10,
        reorderAt: 0,
        syncStatus: SyncStatus.synced,
      ),
    ]);
    await inventory.seedMovements([
      StockMovementModel(
        id: 'm1',
        itemId: 'I1',
        delta: 10,
        reason: StockMovementReason.opening,
        at: _now,
        syncStatus: SyncStatus.synced,
      ),
    ]);

    var snapshot = await reports.load(now: _now);
    expect(snapshot.inventory.onHandUnits, 10);
    expect(await _ledgerSum(inventory), snapshot.inventory.onHandUnits);
    final pendingBefore = snapshot.pendingOperations;

    // Another terminal keeps selling while this device is offline.
    await inventory.recordMovement(
      itemId: 'I1',
      delta: -3,
      reason: StockMovementReason.sale,
      createdOffline: true,
    );

    snapshot = await reports.load(now: _now);
    expect(snapshot.inventory.onHandUnits, 7);
    expect(await _ledgerSum(inventory), snapshot.inventory.onHandUnits);
    expect(snapshot.pendingOperations, pendingBefore + 1);
    expect(snapshot.isStale, isTrue);
  });

  test('receiving a purchase flows through to inventory and reporting', () async {
    await inventory.seedItems([
      InventoryItemModel(
        id: 'I1',
        name: 'صنف',
        unit: 'كجم',
        onHand: 0,
        reorderAt: 0,
        syncStatus: SyncStatus.synced,
      ),
    ]);
    final purchase = await purchases.createPurchase(
      supplierId: 'S',
      supplierName: 'مورد',
      reference: 'PO-2',
      lines: const [
        PurchaseOrderLine(itemId: 'I1', name: 'صنف', quantity: 4, unitCost: 5),
      ],
    );

    final before = await reports.load(now: _now);
    expect(before.inventory.onHandUnits, 0);
    expect(before.purchasing.receivedOrders, 0);

    await purchases.receivePurchase(purchase.id, createdOffline: true);

    final after = await reports.load(now: _now);
    expect(after.inventory.onHandUnits, 4);
    expect(after.inventory.receivedIn, 4);
    expect(
      after.inventory.onHandUnits,
      after.inventory.receivedIn - after.inventory.issuedOut,
    );
    expect(after.purchasing.receivedOrders, 1);
    expect(after.purchasing.receivedValue, 20);
  });
}

Future<double> _ledgerSum(LocalInventoryRepository inventory) async {
  final movements = await inventory.listMovements();
  return movements.fold<double>(0, (sum, m) => sum + m.delta);
}

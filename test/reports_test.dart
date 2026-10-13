import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/data/local/outbox/outbox_entry.dart';
import 'package:rms/src/data/local/outbox/outbox_status.dart';
import 'package:rms/src/domain/models/audit_entry.dart';
import 'package:rms/src/domain/models/cash_session.dart';
import 'package:rms/src/domain/models/collection.dart';
import 'package:rms/src/domain/models/inventory_item.dart';
import 'package:rms/src/domain/models/order.dart';
import 'package:rms/src/domain/models/payment.dart';
import 'package:rms/src/domain/models/purchase_order.dart';
import 'package:rms/src/domain/models/report.dart';
import 'package:rms/src/domain/models/stock_movement.dart';
import 'package:rms/src/domain/models/supplier.dart';

final _now = DateTime(2026, 10, 13, 15);

Order _order(
  DateTime at, {
  double price = 10,
  int quantity = 1,
  SyncStatus status = SyncStatus.synced,
}) =>
    Order(
      localId: 'o-${at.microsecondsSinceEpoch}-$price-$quantity',
      provisionalOrderNumber: 'O',
      items: [
        OrderItem(
          productId: 'p',
          name: 'صنف',
          unitPrice: price,
          quantity: quantity,
        ),
      ],
      createdOffline: false,
      createdAt: at,
      syncStatus: status,
    );

PaymentModel _payment(
  double amount, {
  PaymentMethod method = PaymentMethod.cash,
  SyncStatus status = SyncStatus.synced,
}) =>
    PaymentModel(
      id: 'pay-$amount-${method.name}-${status.name}',
      orderLocalId: 'o',
      orderRef: 'O',
      amount: amount,
      method: method,
      createdAt: _now,
      syncStatus: status,
    );

CollectionModel _collection(double amount) => CollectionModel(
      id: 'col-$amount',
      deliveryId: 'd',
      orderRef: 'O',
      driver: 'dr',
      amount: amount,
      method: PaymentMethod.cash,
      collectedAt: _now,
    );

InventoryItemModel _item(String id, double onHand, double reorderAt) =>
    InventoryItemModel(
      id: id,
      name: id,
      unit: 'كجم',
      onHand: onHand,
      reorderAt: reorderAt,
    );

StockMovementModel _movement(
  String id,
  String itemId,
  double delta, {
  SyncStatus status = SyncStatus.synced,
}) =>
    StockMovementModel(
      id: id,
      itemId: itemId,
      delta: delta,
      reason: delta >= 0 ? StockMovementReason.receipt : StockMovementReason.sale,
      at: _now,
      syncStatus: status,
    );

PurchaseOrderModel _purchase(
  String id,
  double total, {
  PurchaseOrderStatus status = PurchaseOrderStatus.ordered,
}) =>
    PurchaseOrderModel(
      id: id,
      supplierId: 'S',
      supplierName: 'مورد',
      reference: id,
      lines: [
        PurchaseOrderLine(itemId: 'I', name: 'صنف', quantity: 1, unitCost: total),
      ],
      status: status,
      createdAt: _now,
    );

SupplierModel _supplier(String id, {double payable = 0}) =>
    SupplierModel(id: id, name: id, payable: payable);

CashSession _session(
  String id, {
  required bool open,
  double openingFloat = 100,
  double? expected,
  double? counted,
}) =>
    CashSession(
      id: id,
      openedAt: DateTime(2026, 10, 13, 8),
      openingFloat: openingFloat,
      status: open ? CashSessionStatus.open : CashSessionStatus.closed,
      expectedCash: expected,
      countedCash: counted,
      closedAt: open ? null : DateTime(2026, 10, 13, 20),
    );

OutboxEntry _entry(String id, OutboxStatus status, {DateTime? syncedAt}) =>
    OutboxEntry(
      operationId: id,
      entityType: 'order',
      entityId: id,
      operationType: 'createOrder',
      payload: const {},
      schemaVersion: 4,
      idempotencyKey: id,
      createdAt: DateTime(2026, 10, 13, 9),
      lastAttemptAt: syncedAt,
      syncStatus: status,
    );

AuditEntry _audit(String id, DateTime at) => AuditEntry(
      id: id,
      action: AuditAction.recordPayment,
      entityType: 'payment',
      entityId: id,
      summary: 'دفعة',
      at: at,
    );

void main() {
  test('empty snapshot is zeroed but internally consistent', () {
    final snapshot = ReportsSnapshot.from(generatedAt: _now);

    expect(snapshot.sales.total, 0);
    expect(snapshot.sales.orders, 0);
    expect(snapshot.sales.averageTicket, 0);
    expect(snapshot.sales.byDay, hasLength(7));
    expect(snapshot.sales.bestDay, isNull);
    expect(snapshot.payments.net, 0);
    expect(snapshot.inventory.itemCount, 0);
    expect(snapshot.purchasing.openOrders, 0);
    expect(snapshot.cash.variance, 0);
    expect(snapshot.recentAudit, isEmpty);
    expect(snapshot.isStale, isTrue); // nothing acknowledged yet
  });

  test('sales aggregate the rolling window and exclude older days', () {
    final snapshot = ReportsSnapshot.from(
      generatedAt: _now,
      orders: [
        _order(DateTime(2026, 10, 13, 12), price: 30),
        _order(DateTime(2026, 10, 11, 10), price: 20),
        _order(DateTime(2026, 10, 6, 10), price: 100), // outside the window
      ],
    );

    expect(snapshot.sales.orders, 2);
    expect(snapshot.sales.total, 50);
    expect(snapshot.sales.averageTicket, 25);
    expect(snapshot.sales.byDay, hasLength(7));
    expect(snapshot.sales.byDay.first.day, DateTime(2026, 10, 7));
    expect(snapshot.sales.byDay.last.day, DateTime(2026, 10, 13));
    expect(snapshot.sales.byDay.last.total, 30);
    expect(snapshot.sales.bestDay?.day, DateTime(2026, 10, 13));
  });

  test('payments split inflow, refunds and offline balances', () {
    final snapshot = ReportsSnapshot.from(
      generatedAt: _now,
      payments: [
        _payment(100),
        _payment(50, method: PaymentMethod.card),
        _payment(-20),
        _payment(30, status: SyncStatus.pendingSync),
      ],
      collections: [_collection(18)],
    );

    final payments = snapshot.payments;
    expect(payments.count, 4);
    expect(payments.refundCount, 1);
    expect(payments.inflow, 180);
    expect(payments.refunds, 20);
    expect(payments.net, 160);
    expect(payments.cash, 130);
    expect(payments.card, 50);
    expect(payments.offlinePending, 30);
    expect(payments.collections, 18);
    expect(payments.collectedTotal, 178);
  });

  test('inventory on-hand equals the ledger and counts pending lines', () {
    final snapshot = ReportsSnapshot.from(
      generatedAt: _now,
      items: [_item('A', 5, 10), _item('B', 3, 1)],
      movements: [
        _movement('m1', 'A', 10),
        _movement('m2', 'A', -5),
        _movement('m3', 'B', 3, status: SyncStatus.pendingSync),
      ],
    );

    final inventory = snapshot.inventory;
    expect(inventory.itemCount, 2);
    expect(inventory.lowCount, 1); // A (5 <= 10) is low, B (3 > 1) is not
    expect(inventory.onHandUnits, 8);
    expect(inventory.movementCount, 3);
    expect(inventory.pendingMovements, 1);
    expect(inventory.receivedIn - inventory.issuedOut, inventory.onHandUnits);
  });

  test('purchasing summarises open value, received value and payables', () {
    final snapshot = ReportsSnapshot.from(
      generatedAt: _now,
      purchases: [
        _purchase('po1', 100),
        _purchase('po2', 200, status: PurchaseOrderStatus.received),
        _purchase('po3', 300, status: PurchaseOrderStatus.cancelled),
      ],
      suppliers: [_supplier('s1', payable: 1200), _supplier('s2', payable: 480)],
    );

    final purchasing = snapshot.purchasing;
    expect(purchasing.supplierCount, 2);
    expect(purchasing.payables, 1680);
    expect(purchasing.openOrders, 1);
    expect(purchasing.openValue, 100);
    expect(purchasing.receivedOrders, 1);
    expect(purchasing.receivedValue, 200);
  });

  test('cash summarises expected versus counted variance', () {
    final snapshot = ReportsSnapshot.from(
      generatedAt: _now,
      cashSessions: [
        _session('cs1', open: true, openingFloat: 200),
        _session('cs2', open: false, openingFloat: 100, expected: 500, counted: 480),
      ],
    );

    final cash = snapshot.cash;
    expect(cash.openSessions, 1);
    expect(cash.closedSessions, 1);
    expect(cash.openingFloat, 300);
    expect(cash.expectedTotal, 500);
    expect(cash.countedTotal, 480);
    expect(cash.variance, -20);
  });

  test('freshness derives pending, failed, conflict and last sync from outbox', () {
    final snapshot = ReportsSnapshot.from(
      generatedAt: _now,
      outbox: [
        _entry('a', OutboxStatus.pending),
        _entry('b', OutboxStatus.inProgress),
        _entry('c', OutboxStatus.retryableFailure),
        _entry('d', OutboxStatus.conflict),
        _entry('e', OutboxStatus.permanentlyRejected),
        _entry('f', OutboxStatus.synced, syncedAt: DateTime(2026, 10, 13, 12)),
      ],
    );

    expect(snapshot.pendingOperations, 3);
    expect(snapshot.conflictOperations, 1);
    expect(snapshot.failedOperations, 1);
    expect(snapshot.lastSyncedAt, DateTime(2026, 10, 13, 12));
    expect(snapshot.isStale, isTrue); // still has pending work
  });

  test('csv export is flat, machine-readable and properly quoted', () {
    final snapshot = ReportsSnapshot.from(
      generatedAt: _now,
      orders: [_order(DateTime(2026, 10, 13, 12), price: 50)],
      payments: [_payment(100)],
      audit: [_audit('a1', _now)],
    );

    final csv = snapshot.toCsv();
    final lines = csv.split('\n');
    expect(lines.first, 'section,metric,value');
    expect(csv, contains('sales,total,50.00'));
    expect(csv, contains('payments,cash,100.00'));
    expect(csv, contains('meta,generated_at,${_now.toIso8601String()}'));
    expect(lines.every((line) => line.split(',').length == 3), isTrue);
    expect(lines.length, greaterThan(25));
  });
}

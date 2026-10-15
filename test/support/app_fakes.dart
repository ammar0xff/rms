import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/core/config/firebase_config.dart';
import 'package:rms/src/core/di/app_services.dart';
import 'package:rms/src/core/theme/app_theme.dart';
import 'package:rms/src/data/local/outbox/outbox_access.dart';
import 'package:rms/src/data/local/outbox/outbox_entry.dart';
import 'package:rms/src/data/local/outbox/outbox_status.dart';
import 'package:rms/src/data/repositories/approval_repository.dart';
import 'package:rms/src/data/repositories/branch_repository.dart';
import 'package:rms/src/data/repositories/cash_session_repository.dart';
import 'package:rms/src/data/repositories/customer_repository.dart';
import 'package:rms/src/data/repositories/demo_auth_repository.dart';
import 'package:rms/src/data/repositories/delivery_repository.dart';
import 'package:rms/src/data/repositories/inventory_repository.dart';
import 'package:rms/src/data/repositories/kitchen_repository.dart';
import 'package:rms/src/data/repositories/menu_repository.dart';
import 'package:rms/src/data/repositories/order_repository.dart';
import 'package:rms/src/data/repositories/payment_repository.dart';
import 'package:rms/src/data/repositories/purchase_repository.dart';
import 'package:rms/src/data/repositories/reports_repository.dart';
import 'package:rms/src/data/repositories/supplier_repository.dart';
import 'package:rms/src/domain/models/approval_request.dart';
import 'package:rms/src/domain/models/branch.dart';
import 'package:rms/src/domain/models/cash_session.dart';
import 'package:rms/src/domain/models/collection.dart';
import 'package:rms/src/domain/models/customer.dart';
import 'package:rms/src/domain/models/delivery.dart';
import 'package:rms/src/domain/models/inventory_item.dart';
import 'package:rms/src/domain/models/kitchen_ticket.dart';
import 'package:rms/src/domain/models/menu_item.dart';
import 'package:rms/src/domain/models/order.dart';
import 'package:rms/src/domain/models/payment.dart';
import 'package:rms/src/domain/models/purchase_order.dart';
import 'package:rms/src/domain/models/report.dart';
import 'package:rms/src/domain/models/stock_movement.dart';
import 'package:rms/src/domain/models/supplier.dart';

/// Tables and lists WITH rows, at phone width.
///
/// The render sweep proves empty screens; this proves the rows themselves:
/// long Arabic names, money figures, and tags inside every table and list in
/// the app. Overflow fails the test, so each case is a proof, and the content
/// assertions prove the rows actually rendered rather than an empty state
/// standing in for them.
///
/// Fakes implement only what a screen calls; everything else throws through
/// [noSuchMethod], which also pins the screens to their own interfaces. Every
/// screen gets every repository wired, because a data-dependent code path may
/// reach for one the empty sweep never touched.
final _now = DateTime(2026, 10, 15, 12, 30);

/// A long, deliberately awkward name: the case that overflows.
const kLongName = 'مشويات مشكلة كبيرة مع الأرز البسمتي';

OutboxEntry fakeOp(
  String id,
  String entityType,
  String operationType,
  OutboxStatus status, {
  String? error,
}) =>
    OutboxEntry(
      operationId: 'op-$id',
      entityType: entityType,
      entityId: 'e-$id',
      operationType: operationType,
      payload: const {},
      schemaVersion: 1,
      idempotencyKey: 'idem-$id',
      createdAt: _now,
      syncStatus: status,
      lastError: error,
      attemptCount: status == OutboxStatus.pending ? 0 : 2,
    );

class FakeOutbox implements OutboxAccess {
  FakeOutbox(this.entries);

  final List<OutboxEntry> entries;

  @override
  Future<List<OutboxEntry>> all() async => entries;

  @override
  Future<void> save(OutboxEntry entry) async {}

  @override
  Future<int> pruneSynced() async => 0;
}

class _MenuRepo implements MenuRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');

  @override
  Future<List<MenuItemModel>> listMenu(
      {String? category, bool onlyAvailable = false}) async {
    final items = [
      MenuItemModel(
        id: 'm1',
        name: kLongName,
        category: 'المشويات',
        price: 185.5,
        station: 'المشويات',
      ),
      MenuItemModel(
        id: 'm2',
        name: 'بيتزا خضار',
        category: 'البيتزا',
        price: 95,
        station: 'الفرن',
        available: false,
      ),
    ];
    return items
        .where((m) =>
            (category == null || category == 'الكل' || m.category == category))
        .toList();
  }
}

class _KitchenRepo implements KitchenRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');

  KitchenTicketModel _ticket(String id, String station, TicketState state) =>
      KitchenTicketModel(
        id: id,
        orderRef: 'طلب-$id',
        station: station,
        items: const [kLongName],
        state: state,
        createdAt: _now,
      );

  @override
  Future<List<KitchenTicketModel>> listTickets(
      {String? station, Set<TicketState>? states}) async {
    final tickets = [
      _ticket('t1', 'المشويات', TicketState.queued),
      _ticket('t2', 'الفرن', TicketState.preparing),
      _ticket('t3', 'المشويات', TicketState.ready),
    ];
    return tickets
        .where((t) =>
            (station == null || station == 'الكل' || t.station == station) &&
            (states == null || states.contains(t.state)))
        .toList();
  }
}

class _DeliveryRepo implements DeliveryRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');

  @override
  Future<List<DeliveryModel>> listDeliveries() async => [
        DeliveryModel(
          id: 'd1',
          orderRef: 'طلب-توصيل-طويل-001',
          address: 'شارع الجمهورية الطويل، عمارة ١٢، الدور الرابع، شقة ٤٠٢',
          amount: 240.75,
          state: DeliveryState.onRoute,
          createdAt: _now,
          driver: 'مروان ر.',
        ),
        DeliveryModel(
          id: 'd2',
          orderRef: 'طلب-002',
          address: 'ميدان التحرير',
          amount: 120,
          state: DeliveryState.delivered,
          createdAt: _now,
          driver: 'سارة ك.',
        ),
      ];

  @override
  Future<List<DriverModel>> listDrivers() async => const [
        DriverModel(id: 'dr1', name: 'مروان ر.'),
        DriverModel(id: 'dr2', name: 'سارة ك.'),
      ];

  @override
  Future<List<CollectionModel>> listCollections() async => [
        CollectionModel(
          id: 'c1',
          deliveryId: 'd2',
          orderRef: 'طلب-002',
          driver: 'سارة ك.',
          amount: 120,
          method: PaymentMethod.cash,
          collectedAt: _now,
        ),
      ];
}

class _InventoryRepo implements InventoryRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');

  @override
  Future<List<InventoryItemModel>> listItems() async => [
        InventoryItemModel(
          id: 'i1',
          name: 'دجاج متبل بكمية كبيرة للشواء',
          unit: 'كجم',
          onHand: 2,
          reorderAt: 10,
        ),
        InventoryItemModel(
          id: 'i2',
          name: 'أرز',
          unit: 'كجم',
          onHand: 50,
          reorderAt: 10,
        ),
      ];

  @override
  Future<List<StockMovementModel>> listMovements({String? itemId}) async => [
        StockMovementModel(
          id: 's1',
          itemId: 'i1',
          delta: -5,
          reason: StockMovementReason.sale,
          at: _now,
          reference: 'طلب-توصيل-طويل-001',
        ),
      ];
}

class _CustomerRepo implements CustomerRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');

  @override
  Future<List<CustomerModel>> listCustomers() async => [
        CustomerModel(
          id: 'c1',
          name: 'محمد السيد عبد الرحمن الطويل',
          phone: '+20 100 555 0142',
          createdAt: _now,
        ),
        CustomerModel(id: 'c2', name: 'سارة', createdAt: _now),
      ];
}

class _SupplierRepo implements SupplierRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');

  @override
  Future<List<SupplierModel>> listSuppliers() async => [
        SupplierModel(
          id: 's1',
          name: 'مورد اللحوم الرئيسي للفرع',
          payable: 1250.5,
        ),
      ];
}

class _PurchaseRepo implements PurchaseRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');

  @override
  Future<List<PurchaseOrderModel>> listPurchases() async => [
        PurchaseOrderModel(
          id: 'p1',
          supplierId: 's1',
          supplierName: 'مورد اللحوم الرئيسي للفرع',
          reference: 'PO-2026-1042-استلام-مخزن',
          lines: const [
            PurchaseOrderLine(
              itemId: 'i1',
              name: 'دجاج',
              quantity: 20,
              unitCost: 45.5,
            ),
          ],
          createdAt: _now,
        ),
      ];
}

class _PaymentRepo implements PaymentRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');

  @override
  Future<List<PaymentModel>> listPayments() async => [
        PaymentModel(
          id: 'p1',
          orderLocalId: 'o1',
          orderRef: 'طلب-توصيل-طويل-001',
          amount: 240.75,
          method: PaymentMethod.cash,
          createdAt: _now,
        ),
      ];
}

class _CashRepo implements CashSessionRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');

  @override
  Future<List<CashSession>> listSessions() async => [
        CashSession(id: 'cs1', openedAt: _now, openingFloat: 500),
      ];

  @override
  Future<CashSession?> currentSession() async =>
      CashSession(id: 'cs1', openedAt: _now, openingFloat: 500);

  @override
  Future<double> expectedCash(CashSession session) async => 740.75;
}

class _ApprovalRepo implements ApprovalRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');

  @override
  Future<List<ApprovalRequest>> listRequests() async => [
        ApprovalRequest(
          id: 'a1',
          kind: ApprovalKind.refund,
          orderLocalId: 'o1',
          orderRef: 'طلب-توصيل-طويل-001',
          amount: 85.25,
          reason: 'طلب العميل استرداد جزء من المبلغ المدفوع نقدًا',
          requestedAt: _now,
        ),
      ];
}

Order _order(String ref, double total) => Order(
      localId: 'l-$ref',
      provisionalOrderNumber: ref,
      items: [
        OrderItem(productId: 'm1', name: kLongName, unitPrice: total, quantity: 1),
      ],
      createdOffline: false,
      createdAt: _now,
    );

class _OrderRepo implements OrderRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');

  @override
  Future<List<Order>> listOrders() async => [
        _order('طلب-توصيل-طويل-001', 240.75),
        _order('طلب-002', 120),
      ];
}

class _ReportsRepo implements ReportsRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');

  @override
  Future<ReportsSnapshot> load({DateTime? now}) async => ReportsSnapshot(
        generatedAt: _now,
        lastSyncedAt: _now,
        pendingOperations: 2,
        failedOperations: 0,
        conflictOperations: 1,
        sales: ReportSales(
          total: 8412.5,
          orders: 312,
          averageTicket: 26.96,
          byDay: [
            DailySales(day: _now, total: 1200, orders: 45),
            DailySales(
              day: _now.subtract(const Duration(days: 1)),
              total: 980,
              orders: 38,
            ),
          ],
        ),
        payments: const ReportPayments(
          count: 300,
          refundCount: 12,
          inflow: 8000,
          refunds: 320.5,
          net: 7679.5,
          cash: 5000,
          card: 3000,
          offlinePending: 2,
          collections: 40,
          collectionsCount: 40,
          collectedTotal: 1200,
        ),
        inventory: const ReportInventory(
          itemCount: 48,
          lowCount: 3,
          onHandUnits: 1250,
          movementCount: 300,
          pendingMovements: 4,
          receivedIn: 900,
          issuedOut: 640.5,
        ),
        purchasing: const ReportPurchasing(
          supplierCount: 6,
          payables: 4250.75,
          openOrders: 2,
          openValue: 1800,
          receivedOrders: 9,
          receivedValue: 9200.25,
        ),
        cash: const ReportCash(
          openSessions: 1,
          closedSessions: 4,
          openingFloat: 500,
          expectedTotal: 3200.5,
          countedTotal: 3198,
          variance: -2.5,
        ),
        recentAudit: const [],
      );
}

class _BranchRepo implements BranchRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');

  @override
  Future<ConsolidationSnapshot> consolidate({DateTime? now}) async => ConsolidationSnapshot(
        generatedAt: _now,
        branches: [
          BranchBreakdown(
            branch: BranchModel(
              id: 'BR-01',
              name: 'بوابة الشمال الرئيسية',
              code: 'NS-01',
              city: 'القاهرة',
              timezone: 'Africa/Cairo',
              openedAt: _now,
            ),
            rollup: BranchRollup(
              branchId: 'BR-01',
              orders: 312,
              sales: 8412.5,
              collected: 7600,
              inventoryUnits: 1250,
              asOf: _now,
              pending: 3,
            ),
            live: true,
            stale: false,
          ),
        ],
      );
}

/// Every repository, wired. [outbox] is the one a test may want to replace.
AppServices fakeServices({OutboxAccess? outbox}) => AppServices(
      config: const FirebaseConfig.empty(),
      auth: DemoAuthRepository(),
      firebaseReady: false,
      orders: _OrderRepo(),
      menu: _MenuRepo(),
      kitchen: _KitchenRepo(),
      payments: _PaymentRepo(),
      deliveries: _DeliveryRepo(),
      outbox: outbox ?? FakeOutbox([]),
      cashSessions: _CashRepo(),
      approvals: _ApprovalRepo(),
      inventory: _InventoryRepo(),
      suppliers: _SupplierRepo(),
      customers: _CustomerRepo(),
      purchases: _PurchaseRepo(),
      reports: _ReportsRepo(),
      branches: _BranchRepo(),
    );

/// Pump [screen] at phone width with every repository wired.
Future<void> pumpPhone(
  WidgetTester tester,
  Widget screen, {
  OutboxAccess? outbox,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_frame(screen, outbox: outbox));
  await tester.pumpAndSettle();
}

/// Pump [screen] at desktop width with every repository wired.
Future<void> pumpDesktop(
  WidgetTester tester,
  Widget screen, {
  OutboxAccess? outbox,
}) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_frame(screen, outbox: outbox));
  await tester.pumpAndSettle();
}

Widget _frame(Widget screen, {OutboxAccess? outbox}) => AppScope(
      services: fakeServices(outbox: outbox),
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: screen),
      ),
    );

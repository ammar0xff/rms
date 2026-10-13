import '../../data/local/outbox/outbox_entry.dart';
import '../../data/local/outbox/outbox_status.dart';
import 'audit_entry.dart';
import 'cash_session.dart';
import 'collection.dart';
import 'inventory_item.dart';
import 'order.dart';
import 'payment.dart';
import 'purchase_order.dart';
import 'stock_movement.dart';
import 'supplier.dart';

/// One day's sales, used to draw the rolling trend.
class DailySales {
  const DailySales({
    required this.day,
    required this.total,
    required this.orders,
  });

  /// Midnight (local) of the day this bucket covers.
  final DateTime day;
  final double total;
  final int orders;
}

/// Sales KPIs derived from the local order store.
class ReportSales {
  const ReportSales({
    required this.total,
    required this.orders,
    required this.averageTicket,
    required this.byDay,
  });

  final double total;
  final int orders;
  final double averageTicket;

  /// One bucket per day in the window, oldest first.
  final List<DailySales> byDay;

  /// The day with the highest total, or null when every day is zero.
  DailySales? get bestDay {
    DailySales? best;
    for (final day in byDay) {
      if (day.total <= 0) continue;
      if (best == null || day.total > best.total) best = day;
    }
    return best;
  }

  static ReportSales fromOrders(
    List<Order> orders, {
    required DateTime now,
    int windowDays = 7,
  }) {
    final start = DateTime(now.year, now.month, now.day - (windowDays - 1));
    final buckets = <DateTime, DailySales>{};
    for (var i = 0; i < windowDays; i++) {
      final day = DateTime(start.year, start.month, start.day + i);
      buckets[day] = DailySales(day: day, total: 0, orders: 0);
    }

    var total = 0.0;
    var count = 0;
    for (final order in orders) {
      final created = order.createdAt;
      final day = DateTime(created.year, created.month, created.day);
      final bucket = buckets[day];
      if (bucket == null) continue; // older than the reporting window
      buckets[day] = DailySales(
        day: day,
        total: bucket.total + order.total,
        orders: bucket.orders + 1,
      );
      total += order.total;
      count++;
    }

    final byDay = buckets.values.toList()
      ..sort((a, b) => a.day.compareTo(b.day));
    return ReportSales(
      total: total,
      orders: count,
      averageTicket: count == 0 ? 0 : total / count,
      byDay: byDay,
    );
  }
}

/// Money movement derived from the append-only payment and collection logs.
///
/// Payments and collections are never edited, so these sums stay correct under
/// concurrent offline writes and long connectivity gaps.
class ReportPayments {
  const ReportPayments({
    required this.count,
    required this.refundCount,
    required this.inflow,
    required this.refunds,
    required this.net,
    required this.cash,
    required this.card,
    required this.offlinePending,
    required this.collections,
    required this.collectionsCount,
    required this.collectedTotal,
  });

  final int count;
  final int refundCount;
  final double inflow;
  final double refunds;
  final double net;
  final double cash;
  final double card;

  /// Absolute value of payments not yet acknowledged by the backend.
  final double offlinePending;
  final double collections;
  final int collectionsCount;

  /// [net] plus delivery collections.
  final double collectedTotal;

  static ReportPayments fromLedger(
    List<PaymentModel> payments,
    List<CollectionModel> collections,
  ) {
    var inflow = 0.0;
    var refunds = 0.0;
    var cash = 0.0;
    var card = 0.0;
    var offlinePending = 0.0;
    var refundCount = 0;

    for (final payment in payments) {
      if (payment.amount < 0) {
        refunds += -payment.amount;
        refundCount++;
      } else {
        inflow += payment.amount;
        if (payment.method == PaymentMethod.cash) {
          cash += payment.amount;
        } else {
          card += payment.amount;
        }
      }
      if (payment.syncStatus != SyncStatus.synced) {
        offlinePending += payment.amount.abs();
      }
    }

    var collectionTotal = 0.0;
    for (final collection in collections) {
      collectionTotal += collection.amount;
    }

    final net = inflow - refunds;
    return ReportPayments(
      count: payments.length,
      refundCount: refundCount,
      inflow: inflow,
      refunds: refunds,
      net: net,
      cash: cash,
      card: card,
      offlinePending: offlinePending,
      collections: collectionTotal,
      collectionsCount: collections.length,
      collectedTotal: net + collectionTotal,
    );
  }
}

/// Stock position derived from the cached balances and the append-only ledger.
class ReportInventory {
  const ReportInventory({
    required this.itemCount,
    required this.lowCount,
    required this.onHandUnits,
    required this.movementCount,
    required this.pendingMovements,
    required this.receivedIn,
    required this.issuedOut,
  });

  final int itemCount;
  final int lowCount;
  final double onHandUnits;
  final int movementCount;
  final int pendingMovements;

  /// Sum of positive deltas (receipts, returns, upward counts).
  final double receivedIn;

  /// Sum of negative deltas (sales, spoilage, downward counts), as a positive.
  final double issuedOut;

  static ReportInventory fromLedger(
    List<InventoryItemModel> items,
    List<StockMovementModel> movements,
  ) {
    var onHand = 0.0;
    var receivedIn = 0.0;
    var issuedOut = 0.0;
    var pending = 0;
    for (final item in items) {
      onHand += item.onHand;
    }
    for (final movement in movements) {
      if (movement.delta >= 0) {
        receivedIn += movement.delta;
      } else {
        issuedOut += -movement.delta;
      }
      if (movement.syncStatus != SyncStatus.synced) pending++;
    }
    return ReportInventory(
      itemCount: items.length,
      lowCount: items.where((i) => i.isLow).length,
      onHandUnits: onHand,
      movementCount: movements.length,
      pendingMovements: pending,
      receivedIn: receivedIn,
      issuedOut: issuedOut,
    );
  }
}

/// Purchasing position derived from suppliers and purchase orders.
class ReportPurchasing {
  const ReportPurchasing({
    required this.supplierCount,
    required this.payables,
    required this.openOrders,
    required this.openValue,
    required this.receivedOrders,
    required this.receivedValue,
  });

  final int supplierCount;
  final double payables;
  final int openOrders;
  final double openValue;
  final int receivedOrders;
  final double receivedValue;

  static ReportPurchasing fromOrders(
    List<PurchaseOrderModel> purchases,
    List<SupplierModel> suppliers,
  ) {
    var payables = 0.0;
    var openValue = 0.0;
    var receivedValue = 0.0;
    var open = 0;
    var received = 0;
    for (final supplier in suppliers) {
      payables += supplier.payable;
    }
    for (final purchase in purchases) {
      if (purchase.isOpen) {
        open++;
        openValue += purchase.total;
      } else if (purchase.isReceived) {
        received++;
        receivedValue += purchase.total;
      }
    }
    return ReportPurchasing(
      supplierCount: suppliers.length,
      payables: payables,
      openOrders: open,
      openValue: openValue,
      receivedOrders: received,
      receivedValue: receivedValue,
    );
  }
}

/// Drawer session totals, including the counted-versus-expected variance.
class ReportCash {
  const ReportCash({
    required this.openSessions,
    required this.closedSessions,
    required this.openingFloat,
    required this.expectedTotal,
    required this.countedTotal,
    required this.variance,
  });

  final int openSessions;
  final int closedSessions;
  final double openingFloat;

  /// Sum of expected cash across closed sessions.
  final double expectedTotal;

  /// Sum of counted cash across closed sessions.
  final double countedTotal;

  /// [countedTotal] minus [expectedTotal]; non-zero means an unexplained drift.
  final double variance;

  static ReportCash fromSessions(List<CashSession> sessions) {
    var open = 0;
    var closed = 0;
    var openingFloat = 0.0;
    var expected = 0.0;
    var counted = 0.0;
    for (final session in sessions) {
      openingFloat += session.openingFloat;
      if (session.isOpen) {
        open++;
      } else {
        closed++;
        expected += session.expectedCash ?? 0;
        counted += session.countedCash ?? 0;
      }
    }
    return ReportCash(
      openSessions: open,
      closedSessions: closed,
      openingFloat: openingFloat,
      expectedTotal: expected,
      countedTotal: counted,
      variance: counted - expected,
    );
  }
}

/// A single, self-consistent read of every report source.
///
/// The snapshot is a pure function of the local stores plus the outbox, so the
/// same data always yields the same numbers. Because every source is
/// append-only, concurrent offline operations can only add rows — the totals
/// stay internally consistent and [pendingOperations] tells the reader how much
/// has not yet reached the backend.
class ReportsSnapshot {
  const ReportsSnapshot({
    required this.generatedAt,
    required this.lastSyncedAt,
    required this.pendingOperations,
    required this.failedOperations,
    required this.conflictOperations,
    required this.sales,
    required this.payments,
    required this.inventory,
    required this.purchasing,
    required this.cash,
    required this.recentAudit,
  });

  final DateTime generatedAt;

  /// When the backend last acknowledged an operation, or null if never.
  final DateTime? lastSyncedAt;

  /// Operations still awaiting a successful push (including retryable ones).
  final int pendingOperations;

  /// Operations the backend rejected outright.
  final int failedOperations;

  /// Operations parked for explicit user resolution.
  final int conflictOperations;

  final ReportSales sales;
  final ReportPayments payments;
  final ReportInventory inventory;
  final ReportPurchasing purchasing;
  final ReportCash cash;

  /// Most recent audit rows, newest first.
  final List<AuditEntry> recentAudit;

  /// True when the figures may not yet reflect the backend.
  bool get isStale => pendingOperations > 0 || lastSyncedAt == null;

  static ReportsSnapshot from({
    required DateTime generatedAt,
    List<Order> orders = const [],
    List<PaymentModel> payments = const [],
    List<CollectionModel> collections = const [],
    List<CashSession> cashSessions = const [],
    List<InventoryItemModel> items = const [],
    List<StockMovementModel> movements = const [],
    List<PurchaseOrderModel> purchases = const [],
    List<SupplierModel> suppliers = const [],
    List<AuditEntry> audit = const [],
    List<OutboxEntry> outbox = const [],
    int windowDays = 7,
  }) {
    var pending = 0;
    var failed = 0;
    var conflicts = 0;
    DateTime? lastSynced;
    for (final entry in outbox) {
      final status = entry.syncStatus;
      if (status == OutboxStatus.synced) {
        final at = entry.lastAttemptAt ?? entry.createdAt;
        if (lastSynced == null || at.isAfter(lastSynced)) lastSynced = at;
      } else if (status == OutboxStatus.conflict) {
        conflicts++;
      } else if (status == OutboxStatus.permanentlyRejected ||
          status == OutboxStatus.requiresUserAction) {
        failed++;
      } else {
        pending++;
      }
    }

    return ReportsSnapshot(
      generatedAt: generatedAt,
      lastSyncedAt: lastSynced,
      pendingOperations: pending,
      failedOperations: failed,
      conflictOperations: conflicts,
      sales: ReportSales.fromOrders(orders, now: generatedAt, windowDays: windowDays),
      payments: ReportPayments.fromLedger(payments, collections),
      inventory: ReportInventory.fromLedger(items, movements),
      purchasing: ReportPurchasing.fromOrders(purchases, suppliers),
      cash: ReportCash.fromSessions(cashSessions),
      recentAudit: List.unmodifiable(audit),
    );
  }

  /// A flat, machine-readable export of every metric in the snapshot.
  String toCsv() {
    final rows = <List<Object?>>[
      ['section', 'metric', 'value'],
      ['meta', 'generated_at', generatedAt.toIso8601String()],
      ['meta', 'last_synced_at', lastSyncedAt?.toIso8601String() ?? ''],
      ['meta', 'pending_operations', pendingOperations],
      ['meta', 'failed_operations', failedOperations],
      ['meta', 'conflict_operations', conflictOperations],
      ['sales', 'total', sales.total.toStringAsFixed(2)],
      ['sales', 'orders', sales.orders],
      ['sales', 'average_ticket', sales.averageTicket.toStringAsFixed(2)],
      for (final day in sales.byDay)
        ['sales_by_day', day.day.toIso8601String(), day.total.toStringAsFixed(2)],
      ['payments', 'net', payments.net.toStringAsFixed(2)],
      ['payments', 'inflow', payments.inflow.toStringAsFixed(2)],
      ['payments', 'refunds', payments.refunds.toStringAsFixed(2)],
      ['payments', 'cash', payments.cash.toStringAsFixed(2)],
      ['payments', 'card', payments.card.toStringAsFixed(2)],
      ['payments', 'offline_pending', payments.offlinePending.toStringAsFixed(2)],
      ['payments', 'collections', payments.collections.toStringAsFixed(2)],
      ['payments', 'collected_total', payments.collectedTotal.toStringAsFixed(2)],
      ['inventory', 'item_count', inventory.itemCount],
      ['inventory', 'low_count', inventory.lowCount],
      ['inventory', 'on_hand_units', inventory.onHandUnits.toStringAsFixed(2)],
      ['inventory', 'movement_count', inventory.movementCount],
      ['inventory', 'pending_movements', inventory.pendingMovements],
      ['inventory', 'received_in', inventory.receivedIn.toStringAsFixed(2)],
      ['inventory', 'issued_out', inventory.issuedOut.toStringAsFixed(2)],
      ['purchasing', 'supplier_count', purchasing.supplierCount],
      ['purchasing', 'payables', purchasing.payables.toStringAsFixed(2)],
      ['purchasing', 'open_orders', purchasing.openOrders],
      ['purchasing', 'open_value', purchasing.openValue.toStringAsFixed(2)],
      ['purchasing', 'received_orders', purchasing.receivedOrders],
      ['purchasing', 'received_value', purchasing.receivedValue.toStringAsFixed(2)],
      ['cash', 'open_sessions', cash.openSessions],
      ['cash', 'closed_sessions', cash.closedSessions],
      ['cash', 'expected_total', cash.expectedTotal.toStringAsFixed(2)],
      ['cash', 'counted_total', cash.countedTotal.toStringAsFixed(2)],
      ['cash', 'variance', cash.variance.toStringAsFixed(2)],
    ];
    return rows.map((row) => row.map(_csvCell).join(',')).join('\n');
  }

  static String _csvCell(Object? value) {
    final text = value?.toString() ?? '';
    if (text.contains(',') || text.contains('"') || text.contains('\n')) {
      return '"${text.replaceAll('"', '""')}"';
    }
    return text;
  }
}

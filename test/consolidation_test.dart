import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/domain/models/branch.dart';
import 'package:rms/src/domain/models/report.dart';

final _now = DateTime(2026, 10, 13, 15);

BranchModel _branch(
  String id,
  String name, {
  BranchStatus status = BranchStatus.active,
}) =>
    BranchModel(
      id: id,
      name: name,
      code: id,
      city: 'القاهرة',
      timezone: 'Africa/Cairo',
      openedAt: DateTime(2020, 1, 1),
      status: status,
    );

BranchRollup _rollup(
  String id, {
  int orders = 0,
  double sales = 0,
  double collected = 0,
  double units = 0,
  int pending = 0,
  required DateTime asOf,
}) =>
    BranchRollup(
      branchId: id,
      orders: orders,
      sales: sales,
      collected: collected,
      inventoryUnits: units,
      asOf: asOf,
      pending: pending,
    );

void main() {
  group('ConsolidationSnapshot.from', () {
    test('reports missing branches and zero totals when nothing has synced', () {
      final snapshot = ConsolidationSnapshot.from(
        generatedAt: _now,
        branches: [_branch('B1', 'أ'), _branch('B2', 'ب')],
      );

      expect(snapshot.branchCount, 2);
      expect(snapshot.reportingCount, 0);
      expect(snapshot.missingCount, 2);
      expect(snapshot.totalSales, 0);
      expect(snapshot.totalOrders, 0);
      expect(snapshot.localBranch, isNull);
      expect(snapshot.isPartial, isTrue);
      expect(snapshot.branches.every((b) => b.rollup == null), isTrue);
    });

    test('merges the live branch with cached aggregates and sums the totals',
        () {
      final snapshot = ConsolidationSnapshot.from(
        generatedAt: _now,
        branches: [
          _branch('B1', 'أ'),
          _branch('B2', 'ب'),
          _branch('B3', 'ج', status: BranchStatus.paused),
        ],
        aggregates: [
          _rollup(
            'B2',
            orders: 10,
            sales: 100,
            collected: 90,
            units: 5,
            asOf: _now.subtract(const Duration(minutes: 5)),
          ),
          _rollup(
            'B3',
            orders: 4,
            sales: 40,
            collected: 35,
            units: 2,
            asOf: _now.subtract(const Duration(hours: 9)),
          ),
        ],
        local: _rollup(
          'B1',
          orders: 6,
          sales: 60,
          collected: 55,
          units: 3,
          pending: 2,
          asOf: _now,
        ),
        staleAfter: const Duration(hours: 6),
      );

      expect(snapshot.totalOrders, 20);
      expect(snapshot.totalSales, 200);
      expect(snapshot.totalCollected, 180);
      expect(snapshot.totalInventoryUnits, 10);
      expect(snapshot.reportingCount, 3);
      expect(snapshot.activeCount, 2);
      expect(snapshot.staleCount, 1);
      // The device's own branch comes first.
      expect(snapshot.branches.first.branch.id, 'B1');
      expect(snapshot.localBranch?.branch.id, 'B1');
      expect(snapshot.isPartial, isTrue);
    });

    test('the live branch overrides any cached aggregate for the same id', () {
      final snapshot = ConsolidationSnapshot.from(
        generatedAt: _now,
        branches: [_branch('B1', 'أ')],
        aggregates: [_rollup('B1', sales: 999, asOf: _now)],
        local: _rollup('B1', sales: 12, asOf: _now),
      );

      expect(snapshot.totalSales, 12);
      expect(snapshot.branches.single.live, isTrue);
      expect(snapshot.branches.single.stale, isFalse);
    });

    test('marks a cached aggregate stale only past the freshness window', () {
      final fresh = ConsolidationSnapshot.from(
        generatedAt: _now,
        branches: [_branch('B2', 'ب')],
        aggregates: [
          _rollup('B2', asOf: _now.subtract(const Duration(hours: 2))),
        ],
        staleAfter: const Duration(hours: 6),
      );
      expect(fresh.staleCount, 0);
      expect(fresh.isPartial, isFalse);

      final stale = ConsolidationSnapshot.from(
        generatedAt: _now,
        branches: [_branch('B2', 'ب')],
        aggregates: [
          _rollup('B2', asOf: _now.subtract(const Duration(hours: 8))),
        ],
        staleAfter: const Duration(hours: 6),
      );
      expect(stale.staleCount, 1);
    });
  });

  group('BranchRollup.fromReports', () {
    test('derives the rollup from the report read-model', () {
      final reports = ReportsSnapshot(
        generatedAt: _now,
        lastSyncedAt: _now,
        pendingOperations: 2,
        failedOperations: 1,
        conflictOperations: 1,
        sales: const ReportSales(
          total: 250,
          orders: 8,
          averageTicket: 0,
          byDay: [],
        ),
        payments: const ReportPayments(
          count: 0,
          refundCount: 0,
          inflow: 0,
          refunds: 0,
          net: 0,
          cash: 0,
          card: 0,
          offlinePending: 0,
          collections: 0,
          collectionsCount: 0,
          collectedTotal: 230,
        ),
        inventory: const ReportInventory(
          itemCount: 0,
          lowCount: 0,
          onHandUnits: 42,
          movementCount: 0,
          pendingMovements: 0,
          receivedIn: 0,
          issuedOut: 0,
        ),
        purchasing: const ReportPurchasing(
          supplierCount: 0,
          payables: 0,
          openOrders: 0,
          openValue: 0,
          receivedOrders: 0,
          receivedValue: 0,
        ),
        cash: const ReportCash(
          openSessions: 0,
          closedSessions: 0,
          openingFloat: 0,
          expectedTotal: 0,
          countedTotal: 0,
          variance: 0,
        ),
        recentAudit: const [],
      );

      final rollup = BranchRollup.fromReports(branchId: 'B1', reports: reports);

      expect(rollup.sales, 250);
      expect(rollup.orders, 8);
      expect(rollup.collected, 230);
      expect(rollup.inventoryUnits, 42);
      // pending + failed + conflicts.
      expect(rollup.pending, 4);
      expect(rollup.asOf, _now);
    });
  });

  group('ConsolidationSnapshot CSV', () {
    test('exports meta and per-branch rows', () {
      final snapshot = ConsolidationSnapshot.from(
        generatedAt: _now,
        branches: [_branch('B1', 'أ'), _branch('B2', 'ب')],
        aggregates: [
          _rollup('B2', orders: 3, sales: 30, collected: 30, units: 1, asOf: _now),
        ],
        local: _rollup(
          'B1',
          orders: 2,
          sales: 20,
          collected: 20,
          units: 1,
          asOf: _now,
        ),
      );

      final csv = snapshot.toCsv();

      expect(csv, contains('section,metric,value'));
      expect(csv, contains('meta,total_sales,50.00'));
      expect(csv, contains('branch:أ,orders,2'));
      expect(csv, contains('branch:ب,source,cached'));
    });

    test('escapes commas and quotes', () {
      final snapshot = ConsolidationSnapshot.from(
        generatedAt: _now,
        branches: [_branch('B1', 'فرع, "مميز"')],
        local: _rollup('B1', asOf: _now),
      );

      expect(snapshot.toCsv(), contains('"branch:فرع, ""مميز"""'));
    });
  });
}

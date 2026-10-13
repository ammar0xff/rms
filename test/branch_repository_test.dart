import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/data/local/local_database.dart';
import 'package:rms/src/data/repositories/local_branch_repository.dart';
import 'package:rms/src/data/repositories/reports_repository.dart';
import 'package:rms/src/domain/models/branch.dart';
import 'package:rms/src/domain/models/report.dart';

int _seq = 0;

final _now = DateTime(2026, 10, 13, 15);

/// A minimal reports read-model so the branch tests never touch the full store.
class _FakeReports implements ReportsRepository {
  _FakeReports(this.snapshot);

  final ReportsSnapshot snapshot;
  int loads = 0;

  @override
  Future<ReportsSnapshot> load({DateTime? now}) async {
    loads++;
    return snapshot;
  }
}

ReportsSnapshot _reports({
  double sales = 0,
  int orders = 0,
  double collected = 0,
  double onHand = 0,
  int pending = 0,
}) =>
    ReportsSnapshot(
      generatedAt: _now,
      lastSyncedAt: _now,
      pendingOperations: pending,
      failedOperations: 0,
      conflictOperations: 0,
      sales: ReportSales(
        total: sales,
        orders: orders,
        averageTicket: 0,
        byDay: const [],
      ),
      payments: ReportPayments(
        count: 0,
        refundCount: 0,
        inflow: 0,
        refunds: 0,
        net: 0,
        cash: 0,
        card: 0,
        offlinePending: 0,
        collections: collected,
        collectionsCount: 0,
        collectedTotal: collected,
      ),
      inventory: ReportInventory(
        itemCount: 0,
        lowCount: 0,
        onHandUnits: onHand,
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

void main() {
  late LocalDatabase db;

  setUp(() async {
    db = await LocalDatabase.memory('rms_branch_${_seq++}');
  });

  tearDown(() => db.close());

  test('stores and reads the branch directory and the active branch', () async {
    final repo = LocalBranchRepository(
      db,
      reports: _FakeReports(_reports()),
      clock: () => _now,
    );

    expect(await repo.listBranches(), isEmpty);
    expect(await repo.activeBranch(), isNull);

    await repo.cacheBranches([_branch('B2', 'ب'), _branch('B1', 'أ')]);
    final branches = await repo.listBranches();
    // Sorted by name.
    expect(branches.map((b) => b.id), ['B1', 'B2']);

    await repo.setActiveBranch('B2');
    expect((await repo.activeBranch())?.id, 'B2');
  });

  test('replaces the directory by default and upserts when asked', () async {
    final repo = LocalBranchRepository(db, reports: _FakeReports(_reports()));

    await repo.cacheBranches([_branch('B1', 'أ')]);
    await repo.cacheBranches([_branch('B2', 'ب')], replace: false);
    expect((await repo.listBranches()).map((b) => b.id), ['B1', 'B2']);

    await repo.cacheBranches([_branch('B3', 'ج')]);
    expect((await repo.listBranches()).map((b) => b.id), ['B3']);
  });

  test('consolidates the live branch with the cached aggregates', () async {
    final reports = _FakeReports(
      _reports(sales: 500, orders: 12, collected: 480, onHand: 30, pending: 2),
    );
    final repo = LocalBranchRepository(db, reports: reports, clock: () => _now);
    await repo.cacheBranches([_branch('B1', 'أ'), _branch('B2', 'ب')]);
    await repo.setActiveBranch('B1');
    await repo.cacheAggregate(
      BranchRollup(
        branchId: 'B2',
        orders: 20,
        sales: 200,
        collected: 190,
        inventoryUnits: 8,
        asOf: _now.subtract(const Duration(hours: 1)),
      ),
    );

    final snapshot = await repo.consolidate();

    expect(snapshot.generatedAt, _now);
    expect(snapshot.totalSales, 700);
    expect(snapshot.totalOrders, 32);
    expect(snapshot.totalCollected, 670);
    expect(snapshot.totalInventoryUnits, 38);
    expect(snapshot.branches.first.branch.id, 'B1');
    expect(snapshot.branches.first.live, isTrue);
    expect(snapshot.localBranch?.rollup?.pending, 2);

    final cached = snapshot.branches.firstWhere((b) => b.branch.id == 'B2');
    expect(cached.live, isFalse);
    expect(cached.stale, isFalse);
    // The live half is derived from the report read-model once per load.
    expect(reports.loads, 1);
  });

  test('leaves the local rollup empty when no active branch is set', () async {
    final reports = _FakeReports(_reports(sales: 100));
    final repo = LocalBranchRepository(db, reports: reports, clock: () => _now);
    await repo.cacheBranches([_branch('B1', 'أ')]);
    await repo.cacheAggregate(BranchRollup(branchId: 'B1', sales: 50, asOf: _now));

    final snapshot = await repo.consolidate();

    expect(snapshot.localBranch, isNull);
    // Only the cached aggregate contributes.
    expect(snapshot.totalSales, 50);
    expect(reports.loads, 0);
  });

  test('marks an old cached aggregate stale', () async {
    final repo = LocalBranchRepository(
      db,
      reports: _FakeReports(_reports()),
      clock: () => _now,
    );
    await repo.cacheBranches([_branch('B2', 'ب')]);
    await repo.cacheAggregate(
      BranchRollup(
        branchId: 'B2',
        sales: 10,
        asOf: _now.subtract(const Duration(hours: 10)),
      ),
    );

    final snapshot = await repo.consolidate();

    expect(snapshot.staleCount, 1);
    expect(snapshot.isPartial, isTrue);
  });

  test('cachedAggregates returns the stored rollups, sorted by branch', () async {
    final repo = LocalBranchRepository(db, reports: _FakeReports(_reports()));
    await repo.cacheAggregate(BranchRollup(branchId: 'B2', sales: 10, asOf: _now));
    await repo.cacheAggregate(BranchRollup(branchId: 'B1', sales: 20, asOf: _now));

    final aggregates = await repo.cachedAggregates();

    expect(aggregates.map((a) => a.branchId), ['B1', 'B2']);
  });
}

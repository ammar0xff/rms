import 'report.dart';

/// Operational status of a branch within the network.
enum BranchStatus {
  active('نشط'),
  paused('متوقف مؤقتًا'),
  closed('مغلق');

  const BranchStatus(this.label);

  final String label;
}

/// A branch (location) in the multi-branch network.
///
/// The device's own branch is the one selected as active; every other branch
/// arrives through the synced directory and its figures through cached
/// [BranchRollup]s, so consolidation keeps working through an outage.
class BranchModel {
  BranchModel({
    required this.id,
    required this.name,
    required this.code,
    required this.city,
    required this.timezone,
    required this.openedAt,
    this.status = BranchStatus.active,
  });

  final String id;
  final String name;
  final String code;
  final String city;
  final String timezone;
  final DateTime openedAt;
  BranchStatus status;

  bool get isActive => status == BranchStatus.active;

  Map<String, Object?> toRecord() => {
        'id': id,
        'name': name,
        'code': code,
        'city': city,
        'timezone': timezone,
        'status': status.name,
        'openedAt': openedAt.toIso8601String(),
      };

  static BranchModel fromRecord(Map<String, Object?> record) => BranchModel(
        id: record['id'] as String,
        name: record['name'] as String,
        code: record['code'] as String? ?? '',
        city: record['city'] as String? ?? '',
        timezone: record['timezone'] as String? ?? '',
        status: BranchStatus.values
            .byName(record['status'] as String? ?? 'active'),
        openedAt: DateTime.parse(record['openedAt'] as String),
      );
}

/// One branch's contribution to the consolidated view.
///
/// The same shape describes a branch's *live* figures (computed on this device
/// from the local report read-model) and the *cached* figures synced from the
/// backend for every other branch, so the two can be merged without special
/// cases.
class BranchRollup {
  const BranchRollup({
    required this.branchId,
    this.orders = 0,
    this.sales = 0,
    this.collected = 0,
    this.inventoryUnits = 0,
    required this.asOf,
    this.pending = 0,
  });

  final String branchId;
  final int orders;
  final double sales;
  final double collected;

  /// On-hand stock units; the ledger keeps units, not a currency value.
  final double inventoryUnits;

  /// When these figures were produced.
  final DateTime asOf;

  /// Operations at this branch not yet acknowledged by the backend.
  final int pending;

  /// Builds the live rollup for the device's own branch.
  static BranchRollup fromReports({
    required String branchId,
    required ReportsSnapshot reports,
  }) =>
      BranchRollup(
        branchId: branchId,
        orders: reports.sales.orders,
        sales: reports.sales.total,
        collected: reports.payments.collectedTotal,
        inventoryUnits: reports.inventory.onHandUnits,
        asOf: reports.generatedAt,
        pending: reports.pendingOperations +
            reports.failedOperations +
            reports.conflictOperations,
      );

  Map<String, Object?> toRecord() => {
        'branchId': branchId,
        'orders': orders,
        'sales': sales,
        'collected': collected,
        'inventoryUnits': inventoryUnits,
        'asOf': asOf.toIso8601String(),
        'pending': pending,
      };

  static BranchRollup fromRecord(Map<String, Object?> record) => BranchRollup(
        branchId: record['branchId'] as String,
        orders: (record['orders'] as int?) ?? 0,
        sales: (record['sales'] as num?)?.toDouble() ?? 0,
        collected: (record['collected'] as num?)?.toDouble() ?? 0,
        inventoryUnits: (record['inventoryUnits'] as num?)?.toDouble() ?? 0,
        asOf: DateTime.parse(record['asOf'] as String),
        pending: (record['pending'] as int?) ?? 0,
      );
}

/// A branch paired with its figures in the consolidated view.
class BranchBreakdown {
  const BranchBreakdown({
    required this.branch,
    required this.rollup,
    required this.live,
    required this.stale,
  });

  final BranchModel branch;

  /// Null when the branch has neither live nor cached figures yet.
  final BranchRollup? rollup;

  /// True when the figures were computed on this device (its own branch).
  final bool live;

  /// True when the figures are cached and older than the freshness window.
  final bool stale;

  bool get hasData => rollup != null;
}

/// A consolidated, cross-branch read-model.
///
/// Consolidation is a pure function of the branch directory, the cached
/// per-branch rollups and the device's live rollup, so the same inputs always
/// produce the same totals. The device's own branch is always read live from the
/// append-only stores; other branches fall back to their last synced aggregate,
/// which keeps the view available — clearly marked stale — through an outage.
class ConsolidationSnapshot {
  const ConsolidationSnapshot({
    required this.generatedAt,
    required this.branches,
  });

  final DateTime generatedAt;
  final List<BranchBreakdown> branches;

  Iterable<BranchRollup> get _rollups =>
      branches.where((b) => b.hasData).map((b) => b.rollup!);

  int get branchCount => branches.length;

  /// Branches with figures (live or cached).
  int get reportingCount => branches.where((b) => b.hasData).length;

  int get activeCount => branches.where((b) => b.branch.isActive).length;

  int get staleCount => branches.where((b) => b.stale).length;

  /// Branches with no figures at all yet.
  int get missingCount => branches.where((b) => !b.hasData).length;

  int get totalOrders => _rollups.fold(0, (sum, r) => sum + r.orders);

  double get totalSales =>
      _rollups.fold<double>(0, (sum, r) => sum + r.sales);

  double get totalCollected =>
      _rollups.fold<double>(0, (sum, r) => sum + r.collected);

  double get totalInventoryUnits =>
      _rollups.fold<double>(0, (sum, r) => sum + r.inventoryUnits);

  /// The device's own branch, or null when no active branch is set.
  BranchBreakdown? get localBranch {
    for (final breakdown in branches) {
      if (breakdown.live) return breakdown;
    }
    return null;
  }

  /// True when some branches are stale or missing data.
  bool get isPartial => staleCount > 0 || missingCount > 0;

  static ConsolidationSnapshot from({
    required DateTime generatedAt,
    required List<BranchModel> branches,
    List<BranchRollup> aggregates = const [],
    BranchRollup? local,
    Duration staleAfter = const Duration(hours: 6),
  }) {
    final cached = {for (final aggregate in aggregates) aggregate.branchId: aggregate};
    final list = <BranchBreakdown>[];
    for (final branch in branches) {
      final isLocal = local != null && local.branchId == branch.id;
      final rollup = isLocal ? local : cached[branch.id];
      final stale = !isLocal &&
          (rollup == null || generatedAt.difference(rollup.asOf) > staleAfter);
      list.add(
        BranchBreakdown(
          branch: branch,
          rollup: rollup,
          live: isLocal,
          stale: stale,
        ),
      );
    }
    // The device's own branch first, then the rest by name.
    list.sort((a, b) {
      if (a.live != b.live) return a.live ? -1 : 1;
      return a.branch.name.compareTo(b.branch.name);
    });
    return ConsolidationSnapshot(
      generatedAt: generatedAt,
      branches: List.unmodifiable(list),
    );
  }

  /// A flat, machine-readable export of the consolidated figures.
  String toCsv() {
    final rows = <List<Object?>>[
      ['section', 'metric', 'value'],
      ['meta', 'generated_at', generatedAt.toIso8601String()],
      ['meta', 'branch_count', branchCount],
      ['meta', 'reporting_count', reportingCount],
      ['meta', 'stale_count', staleCount],
      ['meta', 'missing_count', missingCount],
      ['meta', 'total_orders', totalOrders],
      ['meta', 'total_sales', totalSales.toStringAsFixed(2)],
      ['meta', 'total_collected', totalCollected.toStringAsFixed(2)],
      ['meta', 'total_inventory_units', totalInventoryUnits.toStringAsFixed(2)],
    ];
    for (final breakdown in branches) {
      final section = 'branch:${breakdown.branch.name}';
      final rollup = breakdown.rollup;
      rows
        ..add([section, 'status', breakdown.branch.status.name])
        ..add([section, 'source', breakdown.live ? 'live' : 'cached'])
        ..add([section, 'stale', breakdown.stale])
        ..add([section, 'as_of', rollup?.asOf.toIso8601String() ?? ''])
        ..add([section, 'orders', rollup?.orders ?? ''])
        ..add([section, 'sales', rollup?.sales.toStringAsFixed(2) ?? ''])
        ..add([section, 'collected', rollup?.collected.toStringAsFixed(2) ?? ''])
        ..add([
          section,
          'inventory_units',
          rollup?.inventoryUnits.toStringAsFixed(2) ?? '',
        ])
        ..add([section, 'pending', rollup?.pending ?? '']);
    }
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

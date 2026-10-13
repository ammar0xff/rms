import 'package:sembast/sembast.dart';

import '../../domain/models/branch.dart';
import '../local/local_database.dart';
import '../local/local_stores.dart';
import 'branch_repository.dart';
import 'reports_repository.dart';

/// Local-first branch directory and consolidation read-model.
///
/// It owns the branch registry and the cached per-branch aggregates, and folds
/// them together with the device's live report read-model into one
/// [ConsolidationSnapshot]. Because the live half is recomputed on every call
/// and the cached half is append/replace-only, a consolidated view stays
/// self-consistent across concurrent offline work and long outages.
class LocalBranchRepository implements BranchRepository {
  LocalBranchRepository(
    this._db, {
    required ReportsRepository reports,
    DateTime Function()? clock,
  })  : _reports = reports,
        _clock = clock ?? DateTime.now;

  final LocalDatabase _db;
  final ReportsRepository _reports;
  final DateTime Function() _clock;

  /// Key under which the active branch id is stored in [LocalStores.meta].
  static const String activeBranchKey = 'activeBranchId';

  /// How old a cached aggregate may be before it is marked stale.
  static const Duration staleAfter = Duration(hours: 6);

  @override
  Future<List<BranchModel>> listBranches() async {
    final snapshots = await LocalStores.branches.find(_db.db);
    final branches =
        snapshots.map((s) => BranchModel.fromRecord(s.value)).toList();
    branches.sort((a, b) => a.name.compareTo(b.name));
    return branches;
  }

  @override
  Future<BranchModel?> activeBranch() async {
    final record = await LocalStores.meta.record(activeBranchKey).get(_db.db);
    final id = record?['value'] as String?;
    if (id == null) return null;
    final branch = await LocalStores.branches.record(id).get(_db.db);
    return branch == null ? null : BranchModel.fromRecord(branch);
  }

  @override
  Future<void> setActiveBranch(String branchId) =>
      LocalStores.meta.record(activeBranchKey).put(_db.db, {'value': branchId});

  @override
  Future<void> cacheBranches(
    List<BranchModel> branches, {
    bool replace = true,
  }) async {
    await _db.transaction((txn) async {
      if (replace) {
        await LocalStores.branches.delete(txn);
      }
      for (final branch in branches) {
        await LocalStores.branches
            .record(branch.id)
            .put(txn, branch.toRecord());
      }
    });
  }

  @override
  Future<void> cacheAggregate(BranchRollup rollup) => LocalStores.branchAggregates
      .record(rollup.branchId)
      .put(_db.db, rollup.toRecord());

  @override
  Future<List<BranchRollup>> cachedAggregates() async {
    final snapshots = await LocalStores.branchAggregates.find(_db.db);
    final rollups =
        snapshots.map((s) => BranchRollup.fromRecord(s.value)).toList();
    rollups.sort((a, b) => a.branchId.compareTo(b.branchId));
    return rollups;
  }

  @override
  Future<ConsolidationSnapshot> consolidate({DateTime? now}) async {
    final generatedAt = now ?? _clock();
    final branches = await listBranches();
    final aggregates = (await LocalStores.branchAggregates.find(_db.db))
        .map((s) => BranchRollup.fromRecord(s.value))
        .toList();

    // The device's own branch is always read live from the local stores; the
    // active branch is the identity the rest of the app writes against.
    BranchRollup? local;
    final active = await activeBranch();
    if (active != null) {
      final reports = await _reports.load(now: generatedAt);
      local = BranchRollup.fromReports(branchId: active.id, reports: reports);
    }

    return ConsolidationSnapshot.from(
      generatedAt: generatedAt,
      branches: branches,
      aggregates: aggregates,
      local: local,
      staleAfter: staleAfter,
    );
  }
}

import '../../domain/models/branch.dart';

/// Local-first access to the branch directory and the consolidated read-model.
///
/// The device's own branch is read live from the append-only stores; every other
/// branch contributes its cached aggregate, so consolidation keeps working
/// during an outage and only degrades its *freshness*, never its consistency.
abstract class BranchRepository {
  Future<List<BranchModel>> listBranches();

  /// The branch this device belongs to, or null when none is provisioned.
  Future<BranchModel?> activeBranch();

  Future<void> setActiveBranch(String branchId);

  Future<void> cacheBranches(List<BranchModel> branches, {bool replace = true});

  /// The cached per-branch figures synced from the backend.
  Future<List<BranchRollup>> cachedAggregates();

  /// Stores the last synced figures for a branch other than this device's.
  Future<void> cacheAggregate(BranchRollup rollup);

  /// Builds the consolidated snapshot from the directory, the cached aggregates
  /// and the device's live rollup. [now] is injectable for deterministic tests.
  Future<ConsolidationSnapshot> consolidate({DateTime? now});
}

import '../../domain/models/report.dart';

/// Local-first reporting read-model.
///
/// Reports are always computed from the on-device stores so they keep working
/// during an outage; [ReportsSnapshot.pendingOperations] is what tells the
/// reader how far behind the backend they may be.
abstract class ReportsRepository {
  /// Builds a single, self-consistent snapshot of every report source.
  ///
  /// [now] is injectable so the rolling window is deterministic in tests.
  Future<ReportsSnapshot> load({DateTime? now});
}

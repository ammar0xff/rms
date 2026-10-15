/// The unsynced local work an install must never drop (AC-35).
///
/// Counts arrive as plain integers so the gate stays pure and can be evaluated
/// offline. The data layer derives them from the transactional outbox — orders,
/// payments, kitchen, delivery and settlement changes all queue there — which
/// keeps this contract free of any storage dependency.
///
/// This lives in its own library so both the readiness gate and the
/// acknowledgement model can depend on it without importing each other.
class LocalWorkSnapshot {
  const LocalWorkSnapshot({
    this.pending = 0,
    this.inProgress = 0,
    this.retryableFailure = 0,
    this.conflict = 0,
    this.requiresUserAction = 0,
    this.permanentlyRejected = 0,
    this.synced = 0,
    this.online = false,
    this.unknownWork = false,
  });

  /// Operations queued but not yet pushed.
  final int pending;

  /// Operations a push has claimed but not yet acknowledged. A crash mid-flight
  /// leaves them here, so they are still owed to the backend.
  final int inProgress;

  /// Operations that failed transiently and will be retried.
  final int retryableFailure;

  /// Operations the backend rejected as conflicting with newer data.
  final int conflict;

  /// Operations parked until a human resolves them.
  final int requiresUserAction;

  /// Operations the backend permanently rejected; they will never sync.
  final int permanentlyRejected;

  /// Operations already acknowledged by the backend.
  final int synced;

  /// Whether the device can currently reach the backend.
  final bool online;

  /// The backlog could not be enumerated at all (no store to read). This is
  /// not the same as an empty backlog: unknown work withholds the install
  /// exactly like unsynced work does, because "cannot see any work" must never
  /// read as "there is no work".
  final bool unknownWork;

  /// Work still owed to the backend that a sync can still deliver.
  int get unsynced => pending + inProgress + retryableFailure;

  /// Work a sync cannot resolve on its own and that needs a human decision.
  int get stuck => conflict + requiresUserAction + permanentlyRejected;

  bool get hasUnsynced => unsynced > 0;

  bool get hasStuck => stuck > 0;
}

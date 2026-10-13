import 'update_decision.dart';

/// The unsynced local work an install must never drop (AC-35).
///
/// Counts arrive as plain integers so the gate stays pure and can be evaluated
/// offline. The data layer derives them from the transactional outbox — orders,
/// payments, kitchen, delivery and settlement changes all queue there — which
/// keeps this contract free of any storage dependency.
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

  /// Work still owed to the backend that a sync can still deliver.
  int get unsynced => pending + inProgress + retryableFailure;

  /// Work a sync cannot resolve on its own and that needs a human decision.
  int get stuck => conflict + requiresUserAction + permanentlyRejected;

  bool get hasUnsynced => unsynced > 0;

  bool get hasStuck => stuck > 0;
}

/// Whether installing the offered release would risk unsynced local work.
enum UpdateReadinessStatus {
  /// The decision offers nothing to install; the gate has nothing to hold.
  noUpdate('لا يوجد تحديث للتثبيت'),

  /// No outstanding local work; the release may be downloaded and installed.
  ready('جاهز للتثبيت'),

  /// Unsynced work exists and the device is online, so sync first.
  awaitingSync('بانتظار مزامنة الأعمال المحلية'),

  /// Unsynced work exists and the device is offline, so a connection is needed.
  offlineBacklog('يلزم اتصال لرفع الأعمال المحلية'),

  /// Work the backend rejected needs a human decision before installing.
  needsAcknowledgement('أعمال محلية معلّقة تحتاج إقرارًا');

  const UpdateReadinessStatus(this.label);

  final String label;
}

/// The outcome of [UpdateReadinessEngine.classify].
class UpdateReadiness {
  const UpdateReadiness({
    required this.status,
    required this.decision,
    required this.work,
  });

  final UpdateReadinessStatus status;
  final UpdateDecision decision;
  final LocalWorkSnapshot work;

  /// Install may begin only when nothing unsynced remains. A mandatory release
  /// does not bypass this: AC-35 requires that work is preserved, never dropped.
  bool get allowsInstall => status == UpdateReadinessStatus.ready;

  /// Worth showing the operator as an interim state, distinct from "nothing to
  /// do" ([UpdateDecisionStatus.upToDate] / ineligible).
  bool get isPending =>
      status != UpdateReadinessStatus.ready &&
      status != UpdateReadinessStatus.noUpdate;

  /// True when the release is mandatory, so it should install as soon as — but
  /// not before — [allowsInstall] becomes true.
  bool get mandatory => decision.status == UpdateDecisionStatus.mandatory;
}

/// Pure, offline-safe install gate.
///
/// It answers a single question: given the update the client already decided to
/// offer, would installing it now risk unsynced work? The rule is deliberately
/// conservative — pending, in-flight, retryable, conflicted, user-action and
/// permanently-rejected records all withhold the install until they reach a
/// terminal state. Nothing here downloads, installs or mutates the outbox.
abstract final class UpdateReadinessEngine {
  static UpdateReadiness classify({
    required UpdateDecision decision,
    required LocalWorkSnapshot work,
    bool workAcknowledged = false,
  }) {
    UpdateReadiness result(UpdateReadinessStatus status) =>
        UpdateReadiness(status: status, decision: decision, work: work);

    if (!decision.isUpdate) {
      return result(UpdateReadinessStatus.noUpdate);
    }
    if (work.hasUnsynced) {
      return result(
        work.online
            ? UpdateReadinessStatus.awaitingSync
            : UpdateReadinessStatus.offlineBacklog,
      );
    }
    if (work.hasStuck && !workAcknowledged) {
      return result(UpdateReadinessStatus.needsAcknowledgement);
    }
    return result(UpdateReadinessStatus.ready);
  }
}

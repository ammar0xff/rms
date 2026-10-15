import 'local_work_snapshot.dart';
import 'update_acknowledgement.dart';
import 'update_decision.dart';

// Re-exported so existing consumers keep importing the snapshot from here while
// the type itself lives in a dependency-free library.
export 'local_work_snapshot.dart';

/// Whether installing the offered release would risk unsynced local work.
enum UpdateReadinessStatus {
  /// The decision offers nothing to install; the gate has nothing to hold.
  noUpdate('مفيش تحديث للتثبيت'),

  /// No outstanding local work; the release may be downloaded and installed.
  ready('جاهز للتثبيت'),

  /// Unsynced work exists and the device is online, so sync first.
  awaitingSync('مستني مزامنة الأعمال المحلية'),

  /// Unsynced work exists and the device is offline, so a connection is needed.
  offlineBacklog('لازم اتصال لرفع الأعمال المحلية'),

  /// Work the backend rejected needs a human decision before installing.
  needsAcknowledgement('أعمال محلية معلّقة محتاجة إقرار');

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
    UpdateAcknowledgement? acknowledgement,
  }) {
    UpdateReadiness result(UpdateReadinessStatus status) =>
        UpdateReadiness(status: status, decision: decision, work: work);

    if (!decision.isUpdate) {
      return result(UpdateReadinessStatus.noUpdate);
    }
    if (work.unknownWork) {
      // The backlog could not be read. Withhold exactly like unsynced work:
      // installing over a backlog you cannot see is how local work gets lost.
      return result(
        work.online
            ? UpdateReadinessStatus.awaitingSync
            : UpdateReadinessStatus.offlineBacklog,
      );
    }
    if (work.hasUnsynced) {
      return result(
        work.online
            ? UpdateReadinessStatus.awaitingSync
            : UpdateReadinessStatus.offlineBacklog,
      );
    }
    // An explicit acknowledgement only counts while it still covers the work on
    // hand. A blanket [workAcknowledged] flag remains available for callers that
    // already evaluated the situation elsewhere.
    final acknowledged =
        workAcknowledged || (acknowledgement?.covers(work) ?? false);
    if (work.hasStuck && !acknowledged) {
      return result(UpdateReadinessStatus.needsAcknowledgement);
    }
    return result(UpdateReadinessStatus.ready);
  }
}

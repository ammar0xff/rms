import 'update_decision.dart';
import 'update_readiness.dart';

/// The outcome of asking "is there anything to do about updates?".
///
/// Lives in the domain because both the service that produces it and the
/// presentation layer that renders it depend on it, and neither should depend
/// on the other.
class UpdateCheckResult {
  const UpdateCheckResult({required this.decision, required this.readiness});

  final UpdateDecision decision;
  final UpdateReadiness readiness;

  /// Whether a release was offered at all.
  bool get hasWork => decision.isUpdate;

  /// Whether the AC-35 gate allows an install right now.
  bool get canInstall => readiness.allowsInstall;

  bool get isMandatory => readiness.mandatory;

  /// True when the gate is withholding an install only because local work is
  /// still owed to the backend.
  bool get isBlockedByLocalWork => readiness.isPending;

  /// A stand-in for "nothing has been checked yet", so the prompt can render
  /// before the first check completes without inventing a decision.
  static final UpdateCheckResult empty = UpdateCheckResult(
    decision: UpdateDecision(status: UpdateDecisionStatus.upToDate),
    readiness: const UpdateReadiness(
      status: UpdateReadinessStatus.noUpdate,
      decision: UpdateDecision(status: UpdateDecisionStatus.upToDate),
      work: LocalWorkSnapshot(),
    ),
  );
}
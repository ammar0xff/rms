import '../models/update_manifest.dart';
import 'update_check_result.dart';
import 'update_prompt_mode.dart';

/// What the client should show, derived from the current check and any in-flight
/// or last-attempt state.
///
/// Kept pure so the escalation rules can be tested without a widget tree. The
/// only asymmetry that matters is severity: a mandatory release becomes a
/// blocking screen, everything else stays dismissible. Nothing here can widen
/// a release's severity — a dismissible update never becomes blocking, and a
/// blocking one is never downgraded because the operator asked.
class UpdatePromptState {
  const UpdatePromptState({
    required this.mode,
    this.check,
    this.progress = 0.0,
    this.detail = '',
  });

  final UpdatePromptMode mode;

  /// The check that produced this prompt, when there is one.
  final UpdateCheckResult? check;

  /// Download progress in 0..1 while an update is being applied.
  final double progress;

  /// Extra context for the operator: the failure reason, or the readiness
  /// explanation when the gate is withholding the install.
  final String detail;

  /// The release this prompt refers to.
  UpdateManifest? get release => check?.decision.release;

  bool get isVisible => mode != UpdatePromptMode.none;

  /// The primary action label.
  String get actionLabel => switch (mode) {
        UpdatePromptMode.working => 'جارٍ التنزيل…',
        UpdatePromptMode.failed => 'إعادة المحاولة',
        UpdatePromptMode.completed => 'تم',
        _ => 'تحديث الآن',
      };

  /// Whether the primary action can be pressed.
  ///
  /// Never true while an update is already running, and never true when the
  /// gate is withholding the install: AC-35 means the button must stay
  /// unavailable until local work is dealt with, not merely be discouraged.
  bool get canApply {
    if (mode == UpdatePromptMode.working) return false;
    if (mode == UpdatePromptMode.none) return false;
    if (mode == UpdatePromptMode.completed) return false;
    final c = check;
    if (c == null) return false;
    return c.readiness.allowsInstall;
  }

  /// The headline the operator reads.
  String get headline => switch (mode) {
        UpdatePromptMode.none => 'أنت على أحدث إصدار',
        UpdatePromptMode.blocking => switch (release?.severity) {
            UpdateSeverity.mandatory => 'تحديث إلزامي مطلوب',
            _ => 'تحديث مطلوب',
          },
        UpdatePromptMode.dismissible => 'تحديث متاح',
        UpdatePromptMode.working => 'جارٍ تثبيت التحديث',
        UpdatePromptMode.failed => 'تعذّر إكمال التحديث',
        UpdatePromptMode.completed => 'تم تثبيت التحديث',
      };

  /// Picks the mode for a freshly completed check.
  ///
  /// In-flight and terminal states are supplied by the caller, because they are
  /// facts about the current attempt rather than about the release.
  static UpdatePromptState derive({
    required UpdateCheckResult check,
    UpdatePromptMode? inFlight,
    String detail = '',
    double progress = 0.0,
  }) {
    if (inFlight != null) {
      return UpdatePromptState(
        mode: inFlight,
        check: check,
        detail: detail,
        progress: progress,
      );
    }

    if (!check.hasWork) {
      return UpdatePromptState(mode: UpdatePromptMode.none, check: check);
    }

    final mode = check.isMandatory
        ? UpdatePromptMode.blocking
        : UpdatePromptMode.dismissible;

    return UpdatePromptState(mode: mode, check: check, detail: detail);
  }
}
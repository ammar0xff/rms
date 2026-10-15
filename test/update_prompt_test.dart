import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/domain/models/update_manifest.dart';
import 'package:rms/src/domain/update/update_check_result.dart';
import 'package:rms/src/domain/update/update_decision.dart';
import 'package:rms/src/domain/update/update_prompt_mode.dart';
import 'package:rms/src/domain/update/update_prompt_state.dart';
import 'package:rms/src/domain/update/update_readiness.dart';

const _sha =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

UpdateManifest _manifest({
  UpdateSeverity severity = UpdateSeverity.recommended,
}) =>
    UpdateManifest(
      releaseId: 'rel-1',
      version: '1.1.0',
      buildNumber: 7,
      platform: UpdatePlatform.android,
      channel: UpdateChannel.production,
      status: ReleaseStatus.active,
      rolloutPercent: 100,
      severity: severity,
      publishedAt: DateTime(2026, 10, 13),
      artifact: ReleaseArtifact(
        reference: 'r',
        sizeBytes: 1024,
        sha256: _sha,
      ),
    );

UpdateCheckResult _check({
  UpdateSeverity severity = UpdateSeverity.recommended,
  LocalWorkSnapshot work = const LocalWorkSnapshot(),
}) {
  final manifest = _manifest(severity: severity);
  final decision = UpdateDecision(
    status: switch (severity) {
      UpdateSeverity.mandatory => UpdateDecisionStatus.mandatory,
      UpdateSeverity.recommended => UpdateDecisionStatus.recommended,
      UpdateSeverity.optional => UpdateDecisionStatus.optional,
    },
    release: manifest,
  );
  return UpdateCheckResult(
    decision: decision,
    readiness: UpdateReadinessEngine.classify(decision: decision, work: work),
  );
}

void main() {
  group('UpdatePromptState.derive', () {
    test('an optional release is dismissible', () {
      final state = UpdatePromptState.derive(
        check: _check(severity: UpdateSeverity.optional),
      );
      expect(state.mode, UpdatePromptMode.dismissible);
      expect(state.mode.isEnforced, isFalse);
      expect(state.isVisible, isTrue);
    });

    test('a recommended release is dismissible', () {
      final state = UpdatePromptState.derive(
        check: _check(severity: UpdateSeverity.recommended),
      );
      expect(state.mode, UpdatePromptMode.dismissible);
    });

    // The whole point of severity: mandatory must not be dismissible.
    test('a mandatory release is blocking', () {
      final state = UpdatePromptState.derive(
        check: _check(severity: UpdateSeverity.mandatory),
      );
      expect(state.mode, UpdatePromptMode.blocking);
      expect(state.mode.isEnforced, isTrue);
    });

    test('up to date shows nothing', () {
      final state = UpdatePromptState.derive(check: UpdateCheckResult.empty);
      expect(state.mode, UpdatePromptMode.none);
      expect(state.isVisible, isFalse);
    });

    test('an in-flight attempt overrides the release severity', () {
      final state = UpdatePromptState.derive(
        check: _check(),
        inFlight: UpdatePromptMode.working,
      );
      expect(state.mode, UpdatePromptMode.working);
      expect(state.mode.isEnforced, isTrue);
    });

    test('a failed attempt is dismissible so the operator can recover', () {
      final state = UpdatePromptState.derive(
        check: _check(),
        inFlight: UpdatePromptMode.failed,
      );
      expect(state.mode, UpdatePromptMode.failed);
      // Enforcing failure trapped the operator on a blocking screen whose only
      // button was disabled, with no path to the stuck work blocking the
      // retry. Dismissing changes nothing installed; the attempt already ended.
      expect(state.mode.isEnforced, isFalse);
    });

    test('a completed attempt is terminal but not enforced', () {
      final state = UpdatePromptState.derive(
        check: _check(),
        inFlight: UpdatePromptMode.completed,
      );
      expect(state.mode, UpdatePromptMode.completed);
      expect(state.mode.isTerminal, isTrue);
      expect(state.mode.isEnforced, isFalse);
    });

    // Mandatory severity must survive the gate being closed: a mandatory
    // release that cannot install is still blocking, not downgraded to a
    // dismissible offer.
    test('a blocked mandatory release stays blocking', () {
      final state = UpdatePromptState.derive(
        check: _check(
          severity: UpdateSeverity.mandatory,
          work: const LocalWorkSnapshot(pending: 2, online: true),
        ),
      );
      expect(state.mode, UpdatePromptMode.blocking);
      expect(state.canApply, isFalse);
    });
  });

  group('UpdatePromptState actions', () {
    test('can apply when the gate allows', () {
      final state = UpdatePromptState.derive(check: _check());
      expect(state.canApply, isTrue);
      expect(state.actionLabel, 'تحديث الآن');
    });

    // AC-35: the button must be unavailable, not merely discouraged.
    test('cannot apply while local work is unsynced', () {
      final state = UpdatePromptState.derive(
        check: _check(work: const LocalWorkSnapshot(pending: 2, online: true)),
      );
      expect(state.canApply, isFalse);
    });

    test('cannot apply while busy', () {
      final state = UpdatePromptState.derive(
        check: _check(),
        inFlight: UpdatePromptMode.working,
      );
      expect(state.canApply, isFalse);
      expect(state.actionLabel, 'جارٍ التنزيل…');
    });

    test('cannot apply once completed', () {
      final state = UpdatePromptState.derive(
        check: _check(),
        inFlight: UpdatePromptMode.completed,
      );
      expect(state.canApply, isFalse);
      expect(state.actionLabel, 'تم');
    });

    test('can retry after a failure once the gate allows', () {
      final state = UpdatePromptState.derive(
        check: _check(),
        inFlight: UpdatePromptMode.failed,
      );
      expect(state.canApply, isTrue);
      expect(state.actionLabel, 'إعادة المحاولة');
    });

    test('nothing to apply when up to date', () {
      final state = UpdatePromptState.derive(check: UpdateCheckResult.empty);
      expect(state.canApply, isFalse);
    });
  });

  group('UpdatePromptState presentation', () {
    test('surfaces the release under offer', () {
      final state = UpdatePromptState.derive(check: _check());
      expect(state.release?.version, '1.1.0');
      expect(state.release?.buildNumber, 7);
    });

    test('a mandatory headline explains itself', () {
      final state = UpdatePromptState.derive(
        check: _check(severity: UpdateSeverity.mandatory),
      );
      expect(state.headline, contains('إلزامي'));
    });

    test('progress is clamped into range', () {
      const state = UpdatePromptState(
        mode: UpdatePromptMode.working,
        progress: 1.4,
      );
      expect(state.progress, 1.4);
    });
  });
}
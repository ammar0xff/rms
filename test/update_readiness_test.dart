import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/domain/update/update_decision.dart';
import 'package:rms/src/domain/update/update_readiness.dart';

UpdateDecision _decision(UpdateDecisionStatus status) =>
    UpdateDecision(status: status);

void main() {
  group('LocalWorkSnapshot counts', () {
    test('unsynced sums the work a sync can still deliver', () {
      const work = LocalWorkSnapshot(
        pending: 2,
        inProgress: 1,
        retryableFailure: 3,
        synced: 40,
      );

      expect(work.unsynced, 6);
      expect(work.hasUnsynced, isTrue);
      expect(work.stuck, 0);
      expect(work.hasStuck, isFalse);
    });

    test('stuck sums the work a sync cannot resolve', () {
      const work = LocalWorkSnapshot(
        conflict: 1,
        requiresUserAction: 2,
        permanentlyRejected: 1,
      );

      expect(work.unsynced, 0);
      expect(work.stuck, 4);
      expect(work.hasStuck, isTrue);
    });
  });

  group('UpdateReadinessEngine', () {
    test('reports nothing to do when the decision offers no update', () {
      for (final status in [
        UpdateDecisionStatus.upToDate,
        UpdateDecisionStatus.ineligible,
      ]) {
        final readiness = UpdateReadinessEngine.classify(
          decision: _decision(status),
          work: const LocalWorkSnapshot(online: true),
        );

        expect(readiness.status, UpdateReadinessStatus.noUpdate);
        expect(readiness.allowsInstall, isFalse);
        expect(readiness.isPending, isFalse);
      }
    });

    test('is ready when the offer is clean and nothing is outstanding', () {
      final readiness = UpdateReadinessEngine.classify(
        decision: _decision(UpdateDecisionStatus.recommended),
        work: const LocalWorkSnapshot(synced: 12, online: true),
      );

      expect(readiness.status, UpdateReadinessStatus.ready);
      expect(readiness.allowsInstall, isTrue);
      expect(readiness.isPending, isFalse);
      expect(readiness.mandatory, isFalse);
    });

    test('waits for sync when unsynced work remains and the device is online',
        () {
      final readiness = UpdateReadinessEngine.classify(
        decision: _decision(UpdateDecisionStatus.optional),
        work: const LocalWorkSnapshot(pending: 2, online: true),
      );

      expect(readiness.status, UpdateReadinessStatus.awaitingSync);
      expect(readiness.allowsInstall, isFalse);
      expect(readiness.isPending, isTrue);
    });

    test('requires a connection when unsynced work remains while offline', () {
      final readiness = UpdateReadinessEngine.classify(
        decision: _decision(UpdateDecisionStatus.recommended),
        work: const LocalWorkSnapshot(inProgress: 1, online: false),
      );

      expect(readiness.status, UpdateReadinessStatus.offlineBacklog);
      expect(readiness.allowsInstall, isFalse);
    });

    test('a transient failure withholds the install like any other backlog',
        () {
      final readiness = UpdateReadinessEngine.classify(
        decision: _decision(UpdateDecisionStatus.recommended),
        work: const LocalWorkSnapshot(retryableFailure: 1, online: true),
      );

      expect(readiness.status, UpdateReadinessStatus.awaitingSync);
      expect(readiness.allowsInstall, isFalse);
    });

    test('requires acknowledgement for work the backend rejected', () {
      final readiness = UpdateReadinessEngine.classify(
        decision: _decision(UpdateDecisionStatus.recommended),
        work: const LocalWorkSnapshot(conflict: 1, online: true),
      );

      expect(readiness.status, UpdateReadinessStatus.needsAcknowledgement);
      expect(readiness.allowsInstall, isFalse);
      expect(readiness.isPending, isTrue);
    });

    test('proceeds once stuck work is acknowledged', () {
      final readiness = UpdateReadinessEngine.classify(
        decision: _decision(UpdateDecisionStatus.recommended),
        work: const LocalWorkSnapshot(requiresUserAction: 3, online: true),
        workAcknowledged: true,
      );

      expect(readiness.status, UpdateReadinessStatus.ready);
      expect(readiness.allowsInstall, isTrue);
    });

    test('acknowledgement does not waive unsynced work', () {
      final readiness = UpdateReadinessEngine.classify(
        decision: _decision(UpdateDecisionStatus.recommended),
        work: const LocalWorkSnapshot(pending: 1, conflict: 1, online: true),
        workAcknowledged: true,
      );

      expect(readiness.status, UpdateReadinessStatus.awaitingSync);
      expect(readiness.allowsInstall, isFalse);
    });

    test('a mandatory release never bypasses the local-work gate', () {
      final readiness = UpdateReadinessEngine.classify(
        decision: _decision(UpdateDecisionStatus.mandatory),
        work: const LocalWorkSnapshot(pending: 5, online: true),
      );

      expect(readiness.status, UpdateReadinessStatus.awaitingSync);
      expect(readiness.allowsInstall, isFalse);
      expect(readiness.mandatory, isTrue);
    });

    test('a mandatory release installs as soon as the backlog drains', () {
      final readiness = UpdateReadinessEngine.classify(
        decision: _decision(UpdateDecisionStatus.mandatory),
        work: const LocalWorkSnapshot(synced: 8, online: true),
      );

      expect(readiness.status, UpdateReadinessStatus.ready);
      expect(readiness.allowsInstall, isTrue);
      expect(readiness.mandatory, isTrue);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/domain/models/update_manifest.dart';
import 'package:rms/src/domain/update/local_work_snapshot.dart';
import 'package:rms/src/domain/update/update_acknowledgement.dart';
import 'package:rms/src/domain/update/update_decision.dart';
import 'package:rms/src/domain/update/update_readiness.dart';

void main() {
  final now = DateTime(2026, 10, 13, 14);
  final ack3 = UpdateAcknowledgement(
    stuckCount: 3,
    acknowledgedAt: now,
    acknowledgedBy: 'manager',
    note: 'reviewed with branch lead',
  );

  UpdateDecision decision() => UpdateDecision(
    status: UpdateDecisionStatus.optional,
    release: UpdateManifest(
      releaseId: 'rel-1',
      version: '1.1.0',
      buildNumber: 42,
      platform: UpdatePlatform.web,
      channel: UpdateChannel.production,
      status: ReleaseStatus.active,
      rolloutPercent: 100,
      severity: UpdateSeverity.optional,
      publishedAt: DateTime(2026, 10, 13),
      artifact: ReleaseArtifact(
        reference: 'https://example.com/app.tar.gz',
        sizeBytes: 1000,
        sha256: 'a' * 64,
      ),
    ),
  );

  group('UpdateAcknowledgement', () {
    test('covers an exact stuck count', () {
      expect(ack3.covers(const LocalWorkSnapshot(conflict: 3)), isTrue);
    });

    test('covers a subset of what was reviewed', () {
      expect(ack3.covers(const LocalWorkSnapshot(conflict: 1)), isTrue);
      expect(
        ack3.covers(const LocalWorkSnapshot(requiresUserAction: 2)),
        isTrue,
      );
    });

    test('does not cover stuck work beyond the reviewed count', () {
      expect(ack3.covers(const LocalWorkSnapshot(conflict: 4)), isFalse);
    });

    test('does not cover an empty snapshot', () {
      expect(ack3.covers(const LocalWorkSnapshot()), isFalse);
    });

    test('never covers unsynced work', () {
      expect(
        ack3.covers(const LocalWorkSnapshot(conflict: 1, pending: 1)),
        isFalse,
      );
      expect(
        ack3.covers(const LocalWorkSnapshot(conflict: 3, retryableFailure: 1)),
        isFalse,
      );
    });

    test('round-trips through a record', () {
      final parsed = UpdateAcknowledgement.tryFromRecord(ack3.toRecord());
      expect(parsed, isNotNull);
      expect(parsed!.stuckCount, 3);
      expect(parsed.acknowledgedAt, now);
      expect(parsed.acknowledgedBy, 'manager');
      expect(parsed.note, 'reviewed with branch lead');
    });

    test('rejects malformed records', () {
      expect(
        UpdateAcknowledgement.tryFromRecord({
          'stuckCount': -1,
          'acknowledgedAt': now.toIso8601String(),
        }),
        isNull,
      );
      expect(
        UpdateAcknowledgement.tryFromRecord(const {
          'stuckCount': 1,
          'acknowledgedAt': 'not-a-date',
        }),
        isNull,
      );
      expect(
        UpdateAcknowledgement.tryFromRecord(const {'stuckCount': 1}),
        isNull,
      );
    });
  });

  group('UpdateReadinessEngine with acknowledgement', () {
    test('stuck work blocks the install by default', () {
      final readiness = UpdateReadinessEngine.classify(
        decision: decision(),
        work: const LocalWorkSnapshot(conflict: 2),
      );
      expect(readiness.status, UpdateReadinessStatus.needsAcknowledgement);
      expect(readiness.allowsInstall, isFalse);
    });

    test('a covering acknowledgement unblocks the install', () {
      final readiness = UpdateReadinessEngine.classify(
        decision: decision(),
        work: const LocalWorkSnapshot(conflict: 2),
        acknowledgement: ack3,
      );
      expect(readiness.status, UpdateReadinessStatus.ready);
      expect(readiness.allowsInstall, isTrue);
    });

    test('a stale acknowledgement does not unblock new stuck work', () {
      final readiness = UpdateReadinessEngine.classify(
        decision: decision(),
        work: const LocalWorkSnapshot(conflict: 9),
        acknowledgement: ack3,
      );
      expect(readiness.status, UpdateReadinessStatus.needsAcknowledgement);
      expect(readiness.allowsInstall, isFalse);
    });

    test('an acknowledgement never overrides unsynced work', () {
      final offline = UpdateReadinessEngine.classify(
        decision: decision(),
        work: const LocalWorkSnapshot(conflict: 1, pending: 1),
        acknowledgement: ack3,
      );
      expect(offline.status, UpdateReadinessStatus.offlineBacklog);
      expect(offline.allowsInstall, isFalse);

      final online = UpdateReadinessEngine.classify(
        decision: decision(),
        work: const LocalWorkSnapshot(conflict: 1, pending: 1, online: true),
        acknowledgement: ack3,
      );
      expect(online.status, UpdateReadinessStatus.awaitingSync);
      expect(online.allowsInstall, isFalse);
    });

    test('the blanket workAcknowledged flag is still honoured', () {
      final readiness = UpdateReadinessEngine.classify(
        decision: decision(),
        work: const LocalWorkSnapshot(conflict: 99),
        workAcknowledged: true,
      );
      expect(readiness.status, UpdateReadinessStatus.ready);
    });

    test('an acknowledgement is irrelevant when nothing is stuck', () {
      final readiness = UpdateReadinessEngine.classify(
        decision: decision(),
        work: const LocalWorkSnapshot(),
        acknowledgement: ack3,
      );
      expect(readiness.status, UpdateReadinessStatus.ready);
    });
  });
}

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/domain/models/update_manifest.dart';
import 'package:rms/src/domain/update/artifact_verifier.dart';
import 'package:rms/src/domain/update/device_update_status.dart';
import 'package:rms/src/domain/update/download_state.dart';
import 'package:rms/src/domain/update/release_audit_event.dart';
import 'package:rms/src/domain/update/update_audit_sink.dart';
import 'package:rms/src/domain/update/update_decision.dart';
import 'package:rms/src/domain/update/update_health_checker.dart';
import 'package:rms/src/domain/update/update_installer.dart';
import 'package:rms/src/domain/update/update_lifecycle_coordinator.dart';
import 'package:rms/src/domain/update/update_migrator.dart';
import 'package:rms/src/domain/update/update_readiness.dart';

final _sha = 'a' * 64;

UpdateManifest _manifest({
  String releaseId = 'rel-1',
  String? rollbackTargetVersion,
}) => UpdateManifest(
  releaseId: releaseId,
  version: '1.1.0',
  buildNumber: 42,
  platform: UpdatePlatform.web,
  channel: UpdateChannel.production,
  status: ReleaseStatus.active,
  rolloutPercent: 100,
  severity: UpdateSeverity.optional,
  publishedAt: DateTime(2026, 10, 13),
  rollbackTargetVersion: rollbackTargetVersion,
  artifact: ReleaseArtifact(
    reference: 'https://example.com/app.tar.gz',
    sizeBytes: 1000,
    sha256: _sha,
  ),
);

class _FakeDownloader implements ArtifactDownloader {
  _FakeDownloader(this.state);

  final DownloadState state;
  int startCalls = 0;

  @override
  Future<DownloadState> start({
    required UpdateManifest manifest,
    required UpdateDecision decision,
  }) async {
    startCalls++;
    return state;
  }

  @override
  Future<void> cancel() async {}

  @override
  Stream<DownloadState> progress() => const Stream<DownloadState>.empty();
}

class _FakeInstaller implements UpdateInstaller {
  _FakeInstaller([this.result = InstallResult.ok]);

  InstallResult result;
  int calls = 0;

  @override
  Future<InstallResult> install({required UpdateManifest manifest}) async {
    calls++;
    return result;
  }
}

class _FakeMigrator implements UpdateMigrator {
  _FakeMigrator([this.result = MigrationResult.ok]);

  MigrationResult result;
  int calls = 0;

  @override
  Future<MigrationResult> migrate({required UpdateManifest manifest}) async {
    calls++;
    return result;
  }
}

class _FakeHealthChecker implements UpdateHealthChecker {
  _FakeHealthChecker([this.status = UpdateHealthStatus.passed]);

  UpdateHealthStatus status;
  int calls = 0;

  @override
  Future<UpdateHealthStatus> check({required UpdateManifest manifest}) async {
    calls++;
    return status;
  }
}

class _MemoryAuditSink implements UpdateAuditSink {
  final List<ReleaseAuditEvent> events = [];

  @override
  Future<void> append(ReleaseAuditEvent event) async => events.add(event);

  List<ReleaseAuditEventType> get types =>
      events.map((e) => e.eventType).toList();
}

DownloadState _downloaded({
  ArtifactVerificationStatus status = ArtifactVerificationStatus.verified,
}) => DownloadState(
  stage: DownloadStage.completed,
  totalBytes: 1000,
  downloadedBytes: 1000,
  progress: 1.0,
  verification: ArtifactVerification(status: status, downloadedBytes: 1000),
);

void main() {
  final now = DateTime(2026, 10, 13, 14);

  UpdateDecision _decision({
    UpdateDecisionStatus status = UpdateDecisionStatus.optional,
    UpdateManifest? release,
    bool requiresMigration = false,
  }) => UpdateDecision(
    status: status,
    release: release ?? _manifest(),
    requiresMigration: requiresMigration,
  );

  UpdateReadiness _readiness(
    UpdateDecision decision, {
    LocalWorkSnapshot work = const LocalWorkSnapshot(),
  }) => UpdateReadinessEngine.classify(decision: decision, work: work);

  UpdateLifecycleCoordinator _coordinator({
    required UpdateDecision decision,
    required UpdateReadiness readiness,
    ArtifactDownloader? downloader,
    UpdateInstaller? installer,
    UpdateMigrator? migrator,
    UpdateHealthChecker? healthChecker,
    _MemoryAuditSink? audit,
  }) => UpdateLifecycleCoordinator(
    decision: decision,
    readiness: readiness,
    downloader: downloader ?? _FakeDownloader(_downloaded()),
    installer: installer ?? _FakeInstaller(),
    migrator: migrator ?? _FakeMigrator(),
    healthChecker: healthChecker ?? _FakeHealthChecker(),
    auditSink: audit,
    now: () => now,
  );

  group('UpdateLifecycleCoordinator', () {
    test('does nothing when the decision offers no update', () async {
      const decision = UpdateDecision(status: UpdateDecisionStatus.upToDate);
      final downloader = _FakeDownloader(_downloaded());
      final installer = _FakeInstaller();

      final result =
          await _coordinator(
            decision: decision,
            readiness: _readiness(decision),
            downloader: downloader,
            installer: installer,
          ).execute();

      expect(result.state, UpdateLifecycleState.idle);
      expect(downloader.startCalls, 0);
      expect(installer.calls, 0);
    });

    test('AC-35: unsynced work withholds the install', () async {
      final decision = _decision();
      final readiness = _readiness(
        decision,
        work: const LocalWorkSnapshot(pending: 3, online: true),
      );
      final downloader = _FakeDownloader(_downloaded());
      final installer = _FakeInstaller();
      final audit = _MemoryAuditSink();

      final result =
          await _coordinator(
            decision: decision,
            readiness: readiness,
            downloader: downloader,
            installer: installer,
            audit: audit,
          ).execute();

      expect(readiness.status, UpdateReadinessStatus.awaitingSync);
      expect(result.state, UpdateLifecycleState.idle);
      // The release stays surfaced, it just is not installed.
      expect(result.releaseId, decision.release!.releaseId);
      expect(downloader.startCalls, 0);
      expect(installer.calls, 0);
      // The refusal itself is on the record: a trail that logs installs but
      // not withheld installs is a lie.
      expect(audit.types, contains(ReleaseAuditEventType.updateWithheld));
    });

    test('waits out a downloader that reports progress asynchronously',
        () async {
      final decision = _decision();
      final installer = _FakeInstaller();
      // Returns `starting` like the production downloader, then completes
      // behind it. Reading only the return value failed every real download
      // at verification, because `starting` carries no verification at all.
      // fromIterable emits on listen, so nothing races the subscription.
      final downloader = _AsyncDownloader(
        first: const DownloadState(
          stage: DownloadStage.starting,
          totalBytes: 1000,
        ),
        states: Stream<DownloadState>.fromIterable([
          const DownloadState(
            stage: DownloadStage.downloading,
            totalBytes: 1000,
            downloadedBytes: 500,
            progress: 0.5,
          ),
          _downloaded(),
        ]),
      );

      final result = await _coordinator(
        decision: decision,
        readiness: _readiness(decision),
        downloader: downloader,
        installer: installer,
      ).execute();

      expect(result.state, UpdateLifecycleState.completed);
      expect(installer.calls, 1);
    });

    test('fails closed when the stream ends without a terminal state',
        () async {
      final decision = _decision();
      final installer = _FakeInstaller();

      final result = await _coordinator(
        decision: decision,
        readiness: _readiness(decision),
        downloader: _AsyncDownloader(
          first: const DownloadState(
            stage: DownloadStage.starting,
            totalBytes: 1000,
          ),
          states: const Stream<DownloadState>.empty(),
        ),
        installer: installer,
      ).execute();

      expect(result.state, UpdateLifecycleState.failed);
      expect(result.failureReason, UpdateFailureReason.downloadFailed);
      expect(installer.calls, 0);
    });

    test(
      'AC-35: a mandatory release is still blocked by unsynced work',
      () async {
        final decision = _decision(status: UpdateDecisionStatus.mandatory);
        final readiness = _readiness(
          decision,
          work: const LocalWorkSnapshot(pending: 1, online: true),
        );
        final installer = _FakeInstaller();

        final result =
            await _coordinator(
              decision: decision,
              readiness: readiness,
              installer: installer,
            ).execute();

        expect(result.state, UpdateLifecycleState.idle);
        expect(installer.calls, 0);
      },
    );

    test('offline backlog also withholds the install', () async {
      final decision = _decision();
      final readiness = _readiness(
        decision,
        work: const LocalWorkSnapshot(pending: 2, online: false),
      );

      final result =
          await _coordinator(
            decision: decision,
            readiness: readiness,
          ).execute();

      expect(readiness.status, UpdateReadinessStatus.offlineBacklog);
      expect(result.state, UpdateLifecycleState.idle);
    });

    test('happy path completes and stamps the applied time', () async {
      final decision = _decision();
      final installer = _FakeInstaller();
      final health = _FakeHealthChecker();

      final result =
          await _coordinator(
            decision: decision,
            readiness: _readiness(decision),
            installer: installer,
            healthChecker: health,
          ).execute();

      expect(result.state, UpdateLifecycleState.completed);
      expect(result.health, UpdateHealthStatus.passed);
      expect(result.releaseId, 'rel-1');
      expect(result.version, '1.1.0');
      expect(result.buildNumber, 42);
      expect(result.progress, 1.0);
      expect(result.requiresRollback, isFalse);
      expect(result.lastAppliedAt, now);
      expect(installer.calls, 1);
      expect(health.calls, 1);
    });

    test('migration runs only when the decision requires it', () async {
      final withMigration = _decision(requiresMigration: true);
      final migrator = _FakeMigrator();

      final migrated =
          await _coordinator(
            decision: withMigration,
            readiness: _readiness(withMigration),
            migrator: migrator,
          ).execute();
      expect(migrator.calls, 1);
      expect(migrated.state, UpdateLifecycleState.completed);

      final without = _decision();
      final untouched = _FakeMigrator();
      await _coordinator(
        decision: without,
        readiness: _readiness(without),
        migrator: untouched,
      ).execute();
      expect(untouched.calls, 0);
    });

    test('audit trail records the lifecycle in order', () async {
      final decision = _decision(requiresMigration: true);
      final audit = _MemoryAuditSink();

      await _coordinator(
        decision: decision,
        readiness: _readiness(decision),
        audit: audit,
      ).execute();

      expect(audit.types, [
        ReleaseAuditEventType.downloadStarted,
        ReleaseAuditEventType.verificationPassed,
        ReleaseAuditEventType.downloadCompleted,
        ReleaseAuditEventType.installStarted,
        ReleaseAuditEventType.installCompleted,
        ReleaseAuditEventType.migrationStarted,
        ReleaseAuditEventType.migrationCompleted,
        ReleaseAuditEventType.healthCheckPassed,
      ]);
      expect(audit.events.every((e) => e.releaseId == 'rel-1'), isTrue);
      expect(audit.events.every((e) => e.eventId.isNotEmpty), isTrue);
    });

    test(
      'health-check failure fails the update and requires rollback',
      () async {
        final decision = _decision();
        final audit = _MemoryAuditSink();

        final result =
            await _coordinator(
              decision: decision,
              readiness: _readiness(decision),
              healthChecker: _FakeHealthChecker(UpdateHealthStatus.failed),
              audit: audit,
            ).execute();

        expect(result.state, UpdateLifecycleState.failed);
        expect(result.failureReason, UpdateFailureReason.healthCheckFailed);
        expect(result.health, UpdateHealthStatus.failed);
        expect(result.requiresRollback, isTrue);
        expect(audit.types, contains(ReleaseAuditEventType.healthCheckFailed));
      },
    );

    test('an inconclusive health check is not treated as success', () async {
      final decision = _decision();

      final result =
          await _coordinator(
            decision: decision,
            readiness: _readiness(decision),
            healthChecker: _FakeHealthChecker(UpdateHealthStatus.inconclusive),
          ).execute();

      expect(result.state, UpdateLifecycleState.failed);
      expect(result.failureReason, UpdateFailureReason.healthCheckFailed);
    });

    test('migration failure requires rollback', () async {
      final decision = _decision(requiresMigration: true);

      final result =
          await _coordinator(
            decision: decision,
            readiness: _readiness(decision),
            migrator: _FakeMigrator(MigrationResult.failed),
          ).execute();

      expect(result.state, UpdateLifecycleState.failed);
      expect(result.failureReason, UpdateFailureReason.migrationFailed);
      expect(result.requiresRollback, isTrue);
    });

    test('install failure is reported without rollback', () async {
      final decision = _decision();

      final result =
          await _coordinator(
            decision: decision,
            readiness: _readiness(decision),
            installer: _FakeInstaller(InstallResult.failed),
          ).execute();

      expect(result.state, UpdateLifecycleState.failed);
      expect(result.failureReason, UpdateFailureReason.installFailed);
      expect(result.requiresRollback, isFalse);
    });

    test('a cancelled install is attributed to the user', () async {
      final decision = _decision();

      final result =
          await _coordinator(
            decision: decision,
            readiness: _readiness(decision),
            installer: _FakeInstaller(InstallResult.cancelled),
          ).execute();

      expect(result.state, UpdateLifecycleState.failed);
      expect(result.failureReason, UpdateFailureReason.userCancelled);
    });

    test('a failed download stops before installing', () async {
      final decision = _decision();
      final installer = _FakeInstaller();

      final result =
          await _coordinator(
            decision: decision,
            readiness: _readiness(decision),
            downloader: _FakeDownloader(
              const DownloadState(
                stage: DownloadStage.failed,
                totalBytes: 1000,
                error: 'connection reset',
              ),
            ),
            installer: installer,
          ).execute();

      expect(result.state, UpdateLifecycleState.failed);
      expect(result.failureReason, UpdateFailureReason.downloadFailed);
      expect(result.errorMessage, 'connection reset');
      expect(installer.calls, 0);
    });

    test('a cancelled download is attributed to the user', () async {
      final decision = _decision();

      final result =
          await _coordinator(
            decision: decision,
            readiness: _readiness(decision),
            downloader: _FakeDownloader(
              const DownloadState(
                stage: DownloadStage.cancelled,
                totalBytes: 1000,
              ),
            ),
          ).execute();

      expect(result.state, UpdateLifecycleState.failed);
      expect(result.failureReason, UpdateFailureReason.userCancelled);
    });

    test('a checksum mismatch stops before installing', () async {
      final decision = _decision();
      final installer = _FakeInstaller();

      final result =
          await _coordinator(
            decision: decision,
            readiness: _readiness(decision),
            downloader: _FakeDownloader(
              _downloaded(status: ArtifactVerificationStatus.checksumMismatch),
            ),
            installer: installer,
          ).execute();

      expect(result.state, UpdateLifecycleState.failed);
      expect(result.failureReason, UpdateFailureReason.verificationFailed);
      expect(installer.calls, 0);
    });

    test('a download with no verification result is rejected', () async {
      final decision = _decision();
      final installer = _FakeInstaller();

      final result =
          await _coordinator(
            decision: decision,
            readiness: _readiness(decision),
            downloader: _FakeDownloader(
              const DownloadState(
                stage: DownloadStage.completed,
                totalBytes: 1000,
                downloadedBytes: 1000,
                progress: 1.0,
              ),
            ),
            installer: installer,
          ).execute();

      expect(result.state, UpdateLifecycleState.failed);
      expect(result.failureReason, UpdateFailureReason.verificationFailed);
      expect(installer.calls, 0);
    });

    test(
      'an unverifiable release is rejected when a checksum exists',
      () async {
        final decision = _decision();
        final installer = _FakeInstaller();

        final result =
            await _coordinator(
              decision: decision,
              readiness: _readiness(decision),
              downloader: _FakeDownloader(
                _downloaded(status: ArtifactVerificationStatus.noChecksum),
              ),
              installer: installer,
            ).execute();

        expect(decision.canVerifyArtifact, isTrue);
        expect(result.state, UpdateLifecycleState.failed);
        expect(result.failureReason, UpdateFailureReason.verificationFailed);
        expect(installer.calls, 0);
      },
    );

    test(
      'a release that publishes no checksum is rejected, not installed',
      () async {
        final release = UpdateManifest(
          releaseId: 'rel-unsigned',
          version: '1.1.0',
          buildNumber: 43,
          platform: UpdatePlatform.web,
          channel: UpdateChannel.production,
          status: ReleaseStatus.active,
          rolloutPercent: 100,
          severity: UpdateSeverity.optional,
          publishedAt: DateTime(2026, 10, 13),
          artifact: ReleaseArtifact(
            reference: 'https://example.com/app.tar.gz',
            sizeBytes: 1000,
            sha256: '',
          ),
        );
        final decision = _decision(release: release);
        final installer = _FakeInstaller();

        final result =
            await _coordinator(
              decision: decision,
              readiness: _readiness(decision),
              downloader: _FakeDownloader(
                _downloaded(status: ArtifactVerificationStatus.noChecksum),
              ),
              installer: installer,
            ).execute();

        // Fail closed: a checksum the client cannot back up is not a checksum.
        // Our publisher always writes one, so nothing legitimate loses here.
        expect(decision.canVerifyArtifact, isFalse);
        expect(result.state, UpdateLifecycleState.failed);
        expect(result.failureReason, UpdateFailureReason.verificationFailed);
        expect(installer.calls, 0);
      },
    );

    test('the rollback target is surfaced from the manifest', () async {
      final decision = _decision(
        release: _manifest(rollbackTargetVersion: '1.0.0'),
      );

      final result =
          await _coordinator(
            decision: decision,
            readiness: _readiness(decision),
            healthChecker: _FakeHealthChecker(UpdateHealthStatus.failed),
          ).execute();

      expect(result.rollbackTargetVersion, '1.0.0');
    });

    test('a throwing installer is contained as a failure', () async {
      final decision = _decision();

      final result =
          await UpdateLifecycleCoordinator(
            decision: decision,
            readiness: _readiness(decision),
            downloader: _FakeDownloader(_downloaded()),
            installer: _ThrowingInstaller(),
            migrator: _FakeMigrator(),
            healthChecker: _FakeHealthChecker(),
            now: () => now,
          ).execute();

      expect(result.state, UpdateLifecycleState.failed);
      expect(result.failureReason, UpdateFailureReason.installFailed);
    });
  });
}

/// An installer that blows up, to prove the coordinator never lets an exception
/// escape to its caller.
class _ThrowingInstaller implements UpdateInstaller {
  @override
  Future<InstallResult> install({required UpdateManifest manifest}) async {
    throw StateError('boom');
  }
}

/// A downloader shaped like production: `start()` hands back a non-terminal
/// state while the transfer runs behind it on the progress stream.
class _AsyncDownloader implements ArtifactDownloader {
  _AsyncDownloader({required this.first, required this.states});

  final DownloadState first;
  final Stream<DownloadState> states;

  @override
  Future<DownloadState> start({
    required UpdateManifest manifest,
    required UpdateDecision decision,
  }) async =>
      first;

  @override
  Future<void> cancel() async {}

  @override
  Stream<DownloadState> progress() => states;
}

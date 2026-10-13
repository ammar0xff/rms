import '../models/update_manifest.dart';
import 'artifact_verifier.dart';
import 'device_update_status.dart';
import 'download_state.dart';
import 'release_audit_event.dart';
import 'update_audit_sink.dart';
import 'update_decision.dart';
import 'update_health_checker.dart';
import 'update_installer.dart';
import 'update_migrator.dart';
import 'update_readiness.dart';

/// Orchestrates the second half of the v1.2 update sequence:
///
/// `protect local work → download/verify → install → migrate → health-check`.
///
/// The coordinator performs no I/O of its own. The download, install, migrate
/// and health-check steps are injected, and audit events are appended to an
/// optional sink, so the whole lifecycle is exercised in unit tests.
///
/// Two invariants are load-bearing:
///
/// * **AC-35.** [UpdateReadiness.allowsInstall] gates the entry. A mandatory
///   release does *not* bypass it — a forced update installs as soon as, but
///   not before, the unsynced backlog clears.
/// * **Fail closed.** The install only proceeds once the artifact has been
///   verified. When integrity cannot be established the attempt stops with
///   [UpdateFailureReason.verificationFailed] rather than installing bytes of
///   unknown provenance.
class UpdateLifecycleCoordinator {
  const UpdateLifecycleCoordinator({
    required this.decision,
    required this.readiness,
    required this.downloader,
    required this.installer,
    required this.migrator,
    required this.healthChecker,
    this.auditSink,
    this.now,
  });

  final UpdateDecision decision;
  final UpdateReadiness readiness;
  final ArtifactDownloader downloader;
  final UpdateInstaller installer;
  final UpdateMigrator migrator;
  final UpdateHealthChecker healthChecker;
  final UpdateAuditSink? auditSink;

  /// Clock, injected so the lifecycle is deterministic under test.
  final DateTime Function()? now;

  DateTime _now() => now?.call() ?? DateTime.now();

  String _nextEventId() => 'evt-${_now().microsecondsSinceEpoch}';

  /// Runs the install lifecycle and returns the terminal [DeviceUpdateStatus].
  ///
  /// Never throws: every failure is reported as a terminal status so the caller
  /// always has something to render.
  Future<DeviceUpdateStatus> execute() async {
    final release = decision.release;
    if (release == null || !decision.isUpdate) {
      return DeviceUpdateStatus(
        state: UpdateLifecycleState.idle,
        statusAt: _now(),
      );
    }

    if (!readiness.allowsInstall) {
      // AC-35: the release stays offered, but nothing is installed while local
      // work is still owed to the backend.
      return DeviceUpdateStatus(
        state: UpdateLifecycleState.idle,
        releaseId: release.releaseId,
        version: release.version,
        buildNumber: release.buildNumber,
        statusAt: _now(),
      );
    }

    var status = DeviceUpdateStatus(
      state: UpdateLifecycleState.readyToInstall,
      releaseId: release.releaseId,
      version: release.version,
      buildNumber: release.buildNumber,
      rollbackTargetVersion: release.rollbackTargetVersion ?? '',
      statusAt: _now(),
    );

    // ---- download + verify -------------------------------------------------
    await _audit(ReleaseAuditEventType.downloadStarted, release);

    final DownloadState download;
    try {
      download = await downloader.start(manifest: release, decision: decision);
    } catch (error) {
      await _audit(ReleaseAuditEventType.failed, release, reason: '$error');
      return status.copyWith(
        state: UpdateLifecycleState.failed,
        failureReason: UpdateFailureReason.downloadFailed,
        errorMessage: '$error',
        statusAt: _now(),
      );
    }

    if (download.stage == DownloadStage.cancelled) {
      await _audit(
        ReleaseAuditEventType.failed,
        release,
        reason: UpdateFailureReason.userCancelled.name,
      );
      return status.copyWith(
        state: UpdateLifecycleState.failed,
        failureReason: UpdateFailureReason.userCancelled,
        errorMessage: download.error,
        statusAt: _now(),
      );
    }

    if (download.stage == DownloadStage.failed) {
      await _audit(
        ReleaseAuditEventType.failed,
        release,
        reason: UpdateFailureReason.downloadFailed.name,
      );
      return status.copyWith(
        state: UpdateLifecycleState.failed,
        failureReason: UpdateFailureReason.downloadFailed,
        errorMessage: download.error,
        statusAt: _now(),
      );
    }

    if (!_verificationSatisfied(download.verification)) {
      final reason = download.verification?.status.name ?? 'unverified';
      await _audit(
        ReleaseAuditEventType.verificationFailed,
        release,
        reason: reason,
      );
      return status.copyWith(
        state: UpdateLifecycleState.failed,
        failureReason: UpdateFailureReason.verificationFailed,
        errorMessage: reason,
        statusAt: _now(),
      );
    }

    await _audit(ReleaseAuditEventType.verificationPassed, release);
    await _audit(ReleaseAuditEventType.downloadCompleted, release);

    // ---- install -----------------------------------------------------------
    status = status.copyWith(
      state: UpdateLifecycleState.installing,
      progress: download.progress,
      statusAt: _now(),
    );
    await _audit(ReleaseAuditEventType.installStarted, release);

    final InstallResult install;
    try {
      install = await installer.install(manifest: release);
    } catch (error) {
      await _audit(ReleaseAuditEventType.failed, release, reason: '$error');
      return status.copyWith(
        state: UpdateLifecycleState.failed,
        failureReason: UpdateFailureReason.installFailed,
        errorMessage: '$error',
        statusAt: _now(),
      );
    }

    if (install != InstallResult.ok) {
      await _audit(ReleaseAuditEventType.failed, release, reason: install.name);
      return status.copyWith(
        state: UpdateLifecycleState.failed,
        failureReason: switch (install) {
          InstallResult.cancelled => UpdateFailureReason.userCancelled,
          _ => UpdateFailureReason.installFailed,
        },
        errorMessage: install.name,
        statusAt: _now(),
      );
    }
    await _audit(ReleaseAuditEventType.installCompleted, release);

    // ---- migrate (only when the decision says the schema advances) ---------
    if (decision.requiresMigration) {
      status = status.copyWith(
        state: UpdateLifecycleState.migrating,
        statusAt: _now(),
      );
      await _audit(ReleaseAuditEventType.migrationStarted, release);

      final MigrationResult migration;
      try {
        migration = await migrator.migrate(manifest: release);
      } catch (error) {
        await _audit(ReleaseAuditEventType.failed, release, reason: '$error');
        return status.copyWith(
          state: UpdateLifecycleState.failed,
          failureReason: UpdateFailureReason.migrationFailed,
          errorMessage: '$error',
          statusAt: _now(),
          requiresRollback: true,
        );
      }

      if (migration != MigrationResult.ok) {
        await _audit(
          ReleaseAuditEventType.failed,
          release,
          reason: migration.name,
        );
        return status.copyWith(
          state: UpdateLifecycleState.failed,
          failureReason: UpdateFailureReason.migrationFailed,
          errorMessage: migration.name,
          statusAt: _now(),
          requiresRollback: true,
        );
      }
      await _audit(ReleaseAuditEventType.migrationCompleted, release);
    }

    // ---- health check ------------------------------------------------------
    status = status.copyWith(
      state: UpdateLifecycleState.healthCheck,
      statusAt: _now(),
    );

    final UpdateHealthStatus health;
    try {
      health = await healthChecker.check(manifest: release);
    } catch (error) {
      await _audit(ReleaseAuditEventType.failed, release, reason: '$error');
      return status.copyWith(
        state: UpdateLifecycleState.failed,
        health: UpdateHealthStatus.failed,
        failureReason: UpdateFailureReason.healthCheckFailed,
        errorMessage: '$error',
        statusAt: _now(),
        requiresRollback: true,
      );
    }

    if (health != UpdateHealthStatus.passed) {
      await _audit(
        ReleaseAuditEventType.healthCheckFailed,
        release,
        reason: health.name,
      );
      return status.copyWith(
        state: UpdateLifecycleState.failed,
        health: health,
        failureReason: UpdateFailureReason.healthCheckFailed,
        errorMessage: health.name,
        statusAt: _now(),
        requiresRollback: true,
      );
    }

    await _audit(ReleaseAuditEventType.healthCheckPassed, release);

    return status.copyWith(
      state: UpdateLifecycleState.completed,
      health: UpdateHealthStatus.passed,
      progress: 1.0,
      statusAt: _now(),
      lastAppliedAt: _now(),
    );
  }

  /// Whether a download may proceed to install.
  ///
  /// A verified checksum always suffices. A manifest that publishes *no*
  /// checksum cannot be verified at all, so accepting it here would be a claim
  /// the client cannot back up — those are rejected too.
  bool _verificationSatisfied(ArtifactVerification? verification) {
    if (verification == null) return false;
    if (verification.isOk) return true;
    return verification.status == ArtifactVerificationStatus.noChecksum &&
        !decision.canVerifyArtifact;
  }

  Future<void> _audit(
    ReleaseAuditEventType type,
    UpdateManifest release, {
    String reason = '',
  }) async {
    final sink = auditSink;
    if (sink == null) return;
    await sink.append(
      ReleaseAuditEvent(
        eventId: _nextEventId(),
        releaseId: release.releaseId,
        occurredAt: _now(),
        eventType: type,
        outcome: type.name,
        reason: reason,
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/data/local/update_store_contracts.dart';
import 'package:rms/src/data/updates/update_service.dart';
import 'package:rms/src/domain/models/update_manifest.dart';
import 'package:rms/src/domain/update/artifact_verifier.dart';
import 'package:rms/src/domain/update/device_update_status.dart';
import 'package:rms/src/domain/update/download_state.dart';
import 'package:rms/src/domain/update/release_audit_event.dart';
import 'package:rms/src/domain/update/update_acknowledgement.dart';
import 'package:rms/src/domain/update/update_audit_sink.dart';
import 'package:rms/src/domain/update/update_decision.dart';
import 'package:rms/src/domain/update/update_health_checker.dart';
import 'package:rms/src/domain/update/update_installer.dart';
import 'package:rms/src/domain/update/update_migrator.dart';
import 'package:rms/src/domain/update/update_readiness.dart';

const _sha =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
final _now = DateTime(2026, 10, 13, 14);

UpdateManifest _manifest({
  UpdatePlatform platform = UpdatePlatform.android,
  UpdateSeverity severity = UpdateSeverity.recommended,
  int? requiredMigrationVersion,
}) =>
    UpdateManifest(
      releaseId: 'rel-1',
      version: '1.1.0',
      buildNumber: 7,
      platform: platform,
      channel: UpdateChannel.production,
      status: ReleaseStatus.active,
      rolloutPercent: 100,
      severity: severity,
      publishedAt: DateTime(2026, 10, 13),
      requiredMigrationVersion: requiredMigrationVersion,
      artifact: ReleaseArtifact(
        reference: 'releases/x/1.1.0/7/app.apk',
        sizeBytes: 1024,
        sha256: _sha,
      ),
    );

UpdateContext _context(UpdatePlatform platform) => UpdateContext(
      installedVersion: '1.0.0',
      platform: platform,
      channel: UpdateChannel.production,
      now: _now,
    );

class _Downloader implements ArtifactDownloader {
  DownloadStage stage = DownloadStage.completed;
  int starts = 0;

  @override
  Future<DownloadState> start({
    required UpdateManifest manifest,
    required UpdateDecision decision,
  }) async {
    starts++;
    return DownloadState(
      stage: stage,
      totalBytes: 1024,
      downloadedBytes: 1024,
      progress: 1.0,
      verification: const ArtifactVerification(
        status: ArtifactVerificationStatus.verified,
        downloadedBytes: 1024,
      ),
    );
  }

  @override
  Future<void> cancel() async {}

  @override
  Stream<DownloadState> progress() => const Stream<DownloadState>.empty();
}

class _Installer implements UpdateInstaller {
  InstallResult result = InstallResult.ok;
  int calls = 0;

  @override
  Future<InstallResult> install({required UpdateManifest manifest}) async {
    calls++;
    return result;
  }
}

class _Migrator implements UpdateMigrator {
  MigrationResult result = MigrationResult.ok;
  int calls = 0;

  @override
  Future<MigrationResult> migrate({required UpdateManifest manifest}) async {
    calls++;
    return result;
  }
}

class _HealthChecker implements UpdateHealthChecker {
  _HealthChecker([this.status = UpdateHealthStatus.passed]);

  UpdateHealthStatus status;
  int calls = 0;

  @override
  Future<UpdateHealthStatus> check({required UpdateManifest manifest}) async {
    calls++;
    return status;
  }
}

class _AuditSink implements UpdateAuditSink {
  final List<ReleaseAuditEvent> events = [];

  @override
  Future<void> append(ReleaseAuditEvent event) async => events.add(event);
}

class _RecordingStatusStore implements UpdateStatusStore {
  DeviceUpdateStatus? saved;

  @override
  Future<DeviceUpdateStatus?> load() async => saved;

  @override
  Future<void> save(DeviceUpdateStatus status) async => saved = status;
}

void main() {
  UpdateService service({
    LocalWorkSnapshot work = const LocalWorkSnapshot(),
    UpdateAcknowledgement? acknowledgement,
    UpdatePlatform platform = UpdatePlatform.android,
    _Downloader? downloader,
    _Installer? installer,
    _Migrator? migrator,
    _HealthChecker? health,
    _AuditSink? audit,
    _RecordingStatusStore? statusStore,
  }) =>
      UpdateService(
        deps: UpdateDeps(
          downloader: downloader ?? _Downloader(),
          installer: installer ?? _Installer(),
          migrator: migrator ?? _Migrator(),
          healthChecker: health ?? _HealthChecker(),
          auditSink: audit,
          statusStore: statusStore,
        ),
        deviceContext: _context(platform),
        work: work,
        acknowledgement: acknowledgement,
        now: () => _now,
      );

  group('UpdateService.check', () {
    test('classifies a release the device can take', () {
      final result = service().check(_manifest());

      expect(result.hasWork, isTrue);
      expect(result.canInstall, isTrue);
      expect(result.isMandatory, isFalse);
      expect(result.isBlockedByLocalWork, isFalse);
    });

    test('reports no work without a manifest', () {
      final result = service().check(null);

      expect(result.hasWork, isFalse);
      expect(result.canInstall, isFalse);
    });

    test('blocks on unsynced local work', () {
      final result = service(
        work: const LocalWorkSnapshot(pending: 2, online: true),
      ).check(_manifest());

      expect(result.canInstall, isFalse);
      expect(result.isBlockedByLocalWork, isTrue);
    });

    test('a mandatory release is still blocked by local work', () {
      final result = service(
        work: const LocalWorkSnapshot(pending: 1, online: true),
      ).check(_manifest(severity: UpdateSeverity.mandatory));

      expect(result.isMandatory, isTrue);
      expect(result.canInstall, isFalse);
      expect(result.isBlockedByLocalWork, isTrue);
    });

    test('an acknowledgement unblocks stuck work', () {
      final ack = UpdateAcknowledgement(
        stuckCount: 2,
        acknowledgedAt: _now,
        acknowledgedBy: 'manager',
      );
      final result = service(
        work: const LocalWorkSnapshot(conflict: 2),
        acknowledgement: ack,
      ).check(_manifest());

      expect(result.canInstall, isTrue);
    });

    test('a release for another platform is ineligible', () {
      final result = service(platform: UpdatePlatform.windows)
          .check(_manifest(platform: UpdatePlatform.android));

      expect(result.hasWork, isFalse);
      expect(result.canInstall, isFalse);
    });
  });

  group('UpdateService.apply', () {
    test('installs and records the terminal status', () async {
      final installer = _Installer();
      final health = _HealthChecker();
      final audit = _AuditSink();
      final statusStore = _RecordingStatusStore();

      final svc = service(
        installer: installer,
        health: health,
        audit: audit,
        statusStore: statusStore,
      );

      final result = await svc.checkAndApply(_manifest());

      expect(result.state, UpdateLifecycleState.completed);
      expect(installer.calls, 1);
      expect(health.calls, 1);
      expect(statusStore.saved?.state, UpdateLifecycleState.completed);
      expect(audit.events, isNotEmpty);
    });

    // The point of the gate. apply() must not be a back door around AC-35.
    test('cannot install while local work is unsynced', () async {
      final downloader = _Downloader();
      final installer = _Installer();
      final statusStore = _RecordingStatusStore();

      final svc = service(
        work: const LocalWorkSnapshot(pending: 5, online: true),
        downloader: downloader,
        installer: installer,
        statusStore: statusStore,
      );

      final result = await svc.checkAndApply(_manifest());

      expect(result.state, UpdateLifecycleState.idle);
      expect(downloader.starts, 0);
      expect(installer.calls, 0);
      expect(statusStore.saved?.state, UpdateLifecycleState.idle);
    });

    test('cannot install a mandatory release while work is stuck and unacknowledged',
        () async {
      final installer = _Installer();
      final svc = service(
        work: const LocalWorkSnapshot(conflict: 3),
        installer: installer,
      );

      final result =
          await svc.checkAndApply(_manifest(severity: UpdateSeverity.mandatory));

      expect(result.state, UpdateLifecycleState.idle);
      expect(installer.calls, 0);
    });

    test('runs the migration when the release requires one', () async {
      final migrator = _Migrator();
      final svc = service(migrator: migrator);

      await svc.checkAndApply(
        _manifest(requiredMigrationVersion: 6),
      );

      expect(migrator.calls, 1);
    });

    test('skips the migration when the release requires none', () async {
      final migrator = _Migrator();
      final svc = service(migrator: migrator);

      await svc.checkAndApply(_manifest());

      expect(migrator.calls, 0);
    });

    test('a failed health check is recorded and requires rollback', () async {
      final statusStore = _RecordingStatusStore();
      final audit = _AuditSink();

      final result = await service(
        health: _HealthChecker(UpdateHealthStatus.failed),
        statusStore: statusStore,
        audit: audit,
      ).checkAndApply(_manifest());

      expect(result.state, UpdateLifecycleState.failed);
      expect(result.requiresRollback, isTrue);
      expect(statusStore.saved?.requiresRollback, isTrue);
    });

    test('a checksum mismatch never reaches the installer', () async {
      final downloader = _Downloader()..stage = DownloadStage.failed;
      final installer = _Installer();

      final result = await service(
        downloader: downloader,
        installer: installer,
      ).checkAndApply(_manifest());

      expect(result.state, UpdateLifecycleState.failed);
      expect(result.failureReason, UpdateFailureReason.downloadFailed);
      expect(installer.calls, 0);
    });

    test('does nothing without a manifest', () async {
      final installer = _Installer();
      final result = await service(installer: installer).checkAndApply(null);

      expect(result.state, UpdateLifecycleState.idle);
      expect(installer.calls, 0);
    });
  });
}
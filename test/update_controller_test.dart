import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/data/local/outbox/outbox_access.dart';
import 'package:rms/src/data/local/outbox/outbox_entry.dart';
import 'package:rms/src/data/local/outbox/outbox_status.dart';
import 'package:rms/src/data/local/update_store_contracts.dart';
import 'package:rms/src/data/repositories/update_repository.dart';
import 'package:rms/src/data/updates/update_runtime.dart';
import 'package:rms/src/data/updates/update_service.dart';
import 'package:rms/src/domain/models/update_manifest.dart';
import 'package:rms/src/domain/update/artifact_verifier.dart';
import 'package:rms/src/domain/update/device_update_status.dart';
import 'package:rms/src/domain/update/download_state.dart';
import 'package:rms/src/domain/update/release_audit_event.dart';
import 'package:rms/src/domain/update/update_audit_sink.dart';
import 'package:rms/src/domain/update/update_decision.dart';
import 'package:rms/src/domain/update/update_health_checker.dart';
import 'package:rms/src/domain/update/update_installer.dart';
import 'package:rms/src/domain/update/update_migrator.dart';
import 'package:rms/src/domain/update/update_prompt_mode.dart';
import 'package:rms/src/features/updates/update_controller.dart';

const _sha =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

UpdateManifest _manifest(UpdateSeverity severity) => UpdateManifest(
      // Deliberately far-future: the decision engine compares this against
      // AppVersion.number, so a fixture pinned to a real version breaks every
      // time the app version is bumped. 99.0.0 is always newer.
      releaseId: 'android-99.0.0-1',
      version: '99.0.0',
      buildNumber: 999,
      platform: UpdatePlatform.android,
      channel: UpdateChannel.production,
      status: ReleaseStatus.active,
      rolloutPercent: 100,
      severity: severity,
      publishedAt: DateTime(2026, 10, 14),
      artifact: const ReleaseArtifact(
        reference:
            'https://github.com/ammar0xff/rms/releases/download/v99.0.0/app.apk',
        sizeBytes: 1024,
        sha256: _sha,
      ),
    );

class _Cache implements UpdateRepository {
  _Cache(this.stored);

  UpdateManifest? stored;

  @override
  Future<UpdateManifest?> cached() async => stored;

  @override
  Future<void> cache(UpdateManifest manifest) async => stored = manifest;
}

/// A mutable outbox, so a check can be repeated against a backlog that grew
/// after the prompt was first shown.
class _Outbox implements OutboxAccess {
  List<OutboxEntry> entries = const [];

  void addPending(int count) {
    entries = [
      for (var i = 0; i < count; i++)
        OutboxEntry(
          operationId: 'op-$i',
          entityType: 'order',
          entityId: 'O-$i',
          operationType: 'upsert',
          payload: const {},
          schemaVersion: 1,
          idempotencyKey: 'idem-$i',
          createdAt: DateTime(2026, 10, 14),
          syncStatus: OutboxStatus.pending,
        ),
    ];
  }

  @override
  Future<List<OutboxEntry>> all() async => entries;

  @override
  Future<void> save(OutboxEntry entry) async {}
}

class _Downloader implements ArtifactDownloader {
  final StreamController<DownloadState> controller =
      StreamController<DownloadState>.broadcast();
  int starts = 0;

  @override
  Future<DownloadState> start({
    required UpdateManifest manifest,
    required UpdateDecision decision,
  }) async {
    starts++;
    return DownloadState(
      stage: DownloadStage.completed,
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
  Stream<DownloadState> progress() => controller.stream;
}

class _Installer implements UpdateInstaller {
  int calls = 0;

  @override
  Future<InstallResult> install({required UpdateManifest manifest}) async {
    calls++;
    return InstallResult.ok;
  }
}

class _Migrator implements UpdateMigrator {
  @override
  Future<MigrationResult> migrate({required UpdateManifest manifest}) async =>
      MigrationResult.ok;
}

class _Health implements UpdateHealthChecker {
  @override
  Future<UpdateHealthStatus> check({required UpdateManifest manifest}) async =>
      UpdateHealthStatus.passed;
}

class _FailingHealth implements UpdateHealthChecker {
  @override
  Future<UpdateHealthStatus> check({required UpdateManifest manifest}) async =>
      UpdateHealthStatus.failed;
}

class _Sink implements UpdateAuditSink {
  final List<ReleaseAuditEvent> events = [];

  @override
  Future<void> append(ReleaseAuditEvent event) async => events.add(event);
}

class _Status implements UpdateStatusStore {
  DeviceUpdateStatus? saved;

  @override
  Future<DeviceUpdateStatus?> load() async => saved;

  @override
  Future<void> save(DeviceUpdateStatus status) async => saved = status;
}

void main() {
  UpdateRuntime runtime({
    required UpdateManifest? manifest,
    OutboxAccess? outbox,
    UpdateInstaller? installer,
    UpdateHealthChecker? health,
    UpdateAuditSink? sink,
    UpdateStatusStore? status,
  }) =>
      UpdateRuntime(
        cache: _Cache(manifest),
        outbox: outbox,
        acknowledgement: null,
        online: () => true,
        buildService: () => UpdateDeps(
          downloader: _Downloader(),
          installer: installer ?? _Installer(),
          migrator: _Migrator(),
          healthChecker: health ?? _Health(),
          auditSink: sink,
          statusStore: status,
        ),
      );

  test('a recommended release surfaces a dismissible prompt', () async {
    final controller = UpdateController(
      runtime: runtime(manifest: _manifest(UpdateSeverity.recommended)),
    );
    addTearDown(controller.dispose);

    await controller.refresh();

    expect(controller.state.mode, UpdatePromptMode.dismissible);
    expect(controller.state.mode.isEnforced, isFalse);
    expect(controller.state.canApply, isTrue);
    expect(controller.state.release?.version, '99.0.0');
  });

  test('a mandatory release surfaces a blocking prompt', () async {
    final controller = UpdateController(
      runtime: runtime(manifest: _manifest(UpdateSeverity.mandatory)),
    );
    addTearDown(controller.dispose);

    await controller.refresh();

    expect(controller.state.mode, UpdatePromptMode.blocking);
    expect(controller.state.mode.isEnforced, isTrue);
  });

  test('no manifest shows nothing', () async {
    final controller = UpdateController(runtime: runtime(manifest: null));
    addTearDown(controller.dispose);

    await controller.refresh();

    expect(controller.state.mode, UpdatePromptMode.none);
    expect(controller.state.isVisible, isFalse);
  });

  test('applying completes and records the terminal status', () async {
    final status = _Status();
    final sink = _Sink();
    final controller = UpdateController(
      runtime: runtime(
        manifest: _manifest(UpdateSeverity.recommended),
        sink: sink,
        status: status,
      ),
    );
    addTearDown(controller.dispose);

    await controller.refresh();
    await controller.apply();

    expect(controller.state.mode, UpdatePromptMode.completed);
    expect(status.saved?.state, UpdateLifecycleState.completed);
    expect(sink.events, isNotEmpty);
  });

  test('apply does nothing before a check has run', () async {
    final installer = _Installer();
    final controller = UpdateController(
      runtime: runtime(
        manifest: _manifest(UpdateSeverity.mandatory),
        installer: installer,
      ),
    );
    addTearDown(controller.dispose);

    await controller.apply();

    expect(installer.calls, 0);
    expect(controller.state.mode, UpdatePromptMode.none);
  });

  // AC-35. The gate must be judged at the moment of the action, not when the
  // prompt first appeared: a backlog that grows afterwards has to stop the
  // install, even for a mandatory release.
  test('a backlog that grows after the prompt was shown blocks the install',
      () async {
    final outbox = _Outbox();
    final installer = _Installer();
    final controller = UpdateController(
      runtime: runtime(
        manifest: _manifest(UpdateSeverity.mandatory),
        outbox: outbox,
        installer: installer,
      ),
    );
    addTearDown(controller.dispose);

    await controller.refresh();
    expect(controller.state.canApply, isTrue);

    outbox.addPending(4);
    await controller.refresh();

    expect(controller.state.canApply, isFalse);
    expect(controller.state.mode, UpdatePromptMode.blocking);
    expect(controller.state.check!.isBlockedByLocalWork, isTrue);

    await controller.apply();
    expect(installer.calls, 0);
  });

  test('clearing the backlog restores the install', () async {
    final outbox = _Outbox()..addPending(2);
    final installer = _Installer();
    final controller = UpdateController(
      runtime: runtime(
        manifest: _manifest(UpdateSeverity.mandatory),
        outbox: outbox,
        installer: installer,
      ),
    );
    addTearDown(controller.dispose);

    await controller.refresh();
    expect(controller.state.canApply, isFalse);

    outbox.entries = const [];
    await controller.refresh();
    expect(controller.state.canApply, isTrue);

    await controller.apply();
    expect(installer.calls, 1);
    expect(controller.state.mode, UpdatePromptMode.completed);
  });

  test('retry re-runs a failed attempt and acknowledge clears it', () async {
    final installer = _Installer();
    final controller = UpdateController(
      runtime: runtime(
        manifest: _manifest(UpdateSeverity.mandatory),
        installer: installer,
        health: _FailingHealth(),
      ),
    );
    addTearDown(controller.dispose);

    await controller.refresh();
    await controller.apply();

    expect(controller.state.mode, UpdatePromptMode.failed);
    expect(controller.state.mode.isEnforced, isFalse);
    final callsAfterFailure = installer.calls;

    // Retry runs the attempt again rather than sitting on the terminal state.
    await controller.retry();
    expect(controller.state.mode, UpdatePromptMode.failed);
    expect(installer.calls, greaterThan(callsAfterFailure));

    // And there is a way out: acknowledge clears the failure and re-checks.
    await controller.acknowledge();
    expect(controller.state.mode, UpdatePromptMode.blocking);
  });
}
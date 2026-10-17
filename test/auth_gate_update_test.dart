import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/app.dart';
import 'package:rms/src/core/config/device_update_context.dart';
import 'package:rms/src/core/config/firebase_config.dart';
import 'package:rms/src/core/di/app_services.dart';
import 'package:rms/src/core/widgets/update_scope.dart';
import 'package:rms/src/data/local/outbox/outbox_access.dart';
import 'package:rms/src/data/local/outbox/outbox_entry.dart';
import 'package:rms/src/data/local/update_store_contracts.dart';
import 'package:rms/src/data/repositories/demo_auth_repository.dart';
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
import 'package:rms/src/features/updates/update_controller.dart';
import 'package:rms/src/features/updates/update_prompt.dart';

const _sha =
    'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';

/// Deliberately far-future: the decision engine compares this against
/// AppVersion.number, so a fixture pinned to a real version breaks every time
/// the app version is bumped.
final _release = UpdateManifest(
  releaseId: 'android-99.0.0-1',
  version: '99.0.0',
  buildNumber: 999,
  platform: currentUpdatePlatform(),
  channel: UpdateChannel.production,
  status: ReleaseStatus.active,
  rolloutPercent: 100,
  severity: UpdateSeverity.recommended,
  publishedAt: DateTime(2026, 10, 17),
  artifact: const ReleaseArtifact(
    reference: 'https://example.invalid/app.apk',
    sizeBytes: 1024,
    sha256: _sha,
  ),
);

/// Counts cache reads so a poll can be asserted rather than inferred from
/// whatever the UI happens to render.
class _CountingCache implements UpdateRepository {
  int reads = 0;

  @override
  Future<UpdateManifest?> cached() async {
    reads++;
    return _release;
  }

  @override
  Future<void> cache(UpdateManifest manifest) async {}

  @override
  Future<void> clear() async {}
}

class _EmptyOutbox implements OutboxAccess {
  @override
  Future<List<OutboxEntry>> all() async => const [];

  @override
  Future<void> save(OutboxEntry entry) async {}

  @override
  Future<int> pruneSynced() async => 0;
}

class _StatusStore implements UpdateStatusStore {
  @override
  Future<DateTime?> snoozedUntil() async => null;

  @override
  Future<void> setSnoozedUntil(DateTime? until) async {}

  @override
  Future<DeviceUpdateStatus?> load() async => null;

  @override
  Future<void> save(DeviceUpdateStatus status) async {}
}

class _AuditSink implements UpdateAuditSink {
  @override
  Future<void> append(ReleaseAuditEvent event) async {}
}

class _Downloader implements ArtifactDownloader {
  @override
  Future<DownloadState> start({
    required UpdateManifest manifest,
    required UpdateDecision decision,
  }) async =>
      const DownloadState(stage: DownloadStage.completed, totalBytes: 1);

  @override
  Future<void> cancel() async {}

  @override
  Stream<DownloadState> progress() => const Stream<DownloadState>.empty();
}

class _Installer implements UpdateInstaller {
  @override
  Future<InstallResult> install({required UpdateManifest manifest}) async =>
      InstallResult.ok;
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

/// Services carrying a real update runtime, which is what the gate needs to
/// build a controller at all. The remote source is left null so the decision
/// comes from the cache without touching the network.
AppServices _services(UpdateRepository cache) => AppServices(
      config: const FirebaseConfig.empty(),
      auth: DemoAuthRepository(),
      firebaseReady: false,
      updateRuntime: UpdateRuntime(
        cache: cache,
        outbox: _EmptyOutbox(),
        online: () => true,
        buildService: () => UpdateDeps(
          downloader: _Downloader(),
          installer: _Installer(),
          migrator: _Migrator(),
          healthChecker: _Health(),
          auditSink: _AuditSink(),
          statusStore: _StatusStore(),
        ),
      ),
      updateStatus: _StatusStore(),
    );

void main() {
  Future<void> pumpGate(WidgetTester tester, AppServices services) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(RmsApp(services: services));
    await tester.pumpAndSettle();
  }

  testWidgets('a signed-out device still polls and is offered the release',
      (tester) async {
    final cache = _CountingCache();
    await pumpGate(tester, _services(cache));

    // The poll belongs to the gate, not the shell: a device parked on the
    // sign-in screen still has to learn a release exists, or it sits on a
    // stale build with nothing ever telling it otherwise.
    expect(cache.reads, greaterThan(0));
    expect(find.byType(UpdatePrompt), findsOneWidget);
    expect(find.text('99.0.0'), findsWidgets);
  });

  testWidgets('one controller is published for every surface', (tester) async {
    await pumpGate(tester, _services(_CountingCache()));

    final context = tester.element(find.byType(UpdateScope).first);
    expect(UpdateScope.of(context), isA<UpdateController>());
    expect(find.byType(UpdateScope), findsOneWidget);
  });

  testWidgets('no runtime means no scope, and the app still renders',
      (tester) async {
    await pumpGate(
      tester,
      AppServices(
        config: const FirebaseConfig.empty(),
        auth: DemoAuthRepository(),
        firebaseReady: false,
      ),
    );

    // Without a runtime there is no controller to publish; the sign-in form
    // must still render rather than reaching for one that was never built.
    expect(find.byType(UpdateScope), findsNothing);
    expect(find.text('ادخل'), findsOneWidget);
  });
}

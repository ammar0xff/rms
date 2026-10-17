import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/app.dart';
import 'package:rms/src/core/config/device_update_context.dart';
import 'package:rms/src/core/config/firebase_config.dart';
import 'package:rms/src/core/di/app_services.dart';
import 'package:rms/src/core/widgets/update_scope.dart';
import 'package:rms/src/data/local/local_database.dart';
import 'package:rms/src/data/local/outbox/outbox_access.dart';
import 'package:rms/src/data/local/outbox/outbox_entry.dart';
import 'package:rms/src/data/repositories/demo_auth_repository.dart';
import 'package:rms/src/data/repositories/update_repository.dart';
import 'package:rms/src/domain/models/update_manifest.dart';
import 'package:rms/src/features/updates/update_controller.dart';
import 'package:rms/src/features/updates/update_prompt.dart';
import 'package:sembast/sembast_memory.dart';

const _sha =
    'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';

/// Counts how often the manifest cache is read, so a poll can be asserted
/// rather than inferred from whatever the UI happens to render.
class _CountingUpdates implements UpdateRepository {
  _CountingUpdates(this.manifest);

  final UpdateManifest? manifest;
  int reads = 0;

  @override
  Future<UpdateManifest?> cached() async {
    reads++;
    return manifest;
  }

  @override
  Future<void> cache(UpdateManifest manifest) async {}

  @override
  Future<void> clear() async {}
}

/// An enumerated-empty outbox. Null would mean "backlog unreadable" and
/// withhold the install; these cases need "readable and empty".
class _EmptyOutbox implements OutboxAccess {
  @override
  Future<List<OutboxEntry>> all() async => const [];

  @override
  Future<void> save(OutboxEntry entry) async {}

  @override
  Future<int> pruneSynced() async => 0;
}

UpdateManifest _manifest(String version) => UpdateManifest(
      version: version,
      releaseId: 'r-$version',
      buildNumber: 1,
      publishedAt: DateTime(2026, 10, 17),
      status: ReleaseStatus.active,
      channel: UpdateChannel.production,
      platform: currentUpdatePlatform(),
      severity: UpdateSeverity.recommended,
      rolloutPercent: 100,
      minSupportedVersion: '0.0.0',
      artifact: const ReleaseArtifact(
        reference: 'https://example.invalid/app.apk',
        sizeBytes: 1,
        sha256: _sha,
      ),
    );

/// Services with a local store, which is what makes an update runtime
/// exist at all. Built through [runAsync]: opening a store is real async,
/// which the widget-test zone will not drive on its own.
Future<AppServices> _services(UpdateRepository updates) async => AppServices(
      config: const FirebaseConfig.empty(),
      auth: DemoAuthRepository(),
      firebaseReady: false,
      database: LocalDatabase.fromDatabase(await databaseFactoryMemory
          .openDatabase('rms_auth_gate_${DateTime.now().microsecondsSinceEpoch}')),
      updates: updates,
      outbox: _EmptyOutbox(),
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
    final updates = _CountingUpdates(_manifest('99.0.0'));
    final services = await tester.runAsync(() => _services(updates));
    await pumpGate(tester, services!);

    // The poll belongs to the gate, not the shell: a device parked on the
    // sign-in screen still has to learn a release exists, or it sits on a
    // stale build with nothing ever telling it otherwise.
    expect(updates.reads, greaterThan(0));
    expect(find.byType(UpdatePrompt), findsOneWidget);
    expect(find.text('99.0.0'), findsWidgets);
  });

  testWidgets('one controller is published for every surface',
      (tester) async {
    final services = await tester.runAsync(() => _services(_CountingUpdates(null)));
    await pumpGate(tester, services!);

    final context = tester.element(find.byType(UpdateScope).first);
    expect(UpdateScope.of(context), isA<UpdateController>());
    expect(find.byType(UpdateScope), findsOneWidget);
  });

  testWidgets('no local store means no scope, and the app still renders',
      (tester) async {
    await pumpGate(
      tester,
      AppServices(
        config: const FirebaseConfig.empty(),
        auth: DemoAuthRepository(),
        firebaseReady: false,
      ),
    );

    expect(find.byType(UpdateScope), findsNothing);
    expect(find.text('ادخل'), findsOneWidget);
  });
}

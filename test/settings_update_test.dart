import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/app.dart';
import 'package:rms/src/core/config/device_update_context.dart';
import 'package:rms/src/core/config/firebase_config.dart';
import 'package:rms/src/core/di/app_services.dart';
import 'package:rms/src/core/widgets/status.dart';
import 'package:rms/src/data/local/outbox/outbox_access.dart';
import 'package:rms/src/data/local/outbox/outbox_entry.dart';
import 'package:rms/src/data/repositories/demo_auth_repository.dart';
import 'package:rms/src/data/repositories/update_repository.dart';
import 'package:rms/src/domain/models/update_manifest.dart';

final _sha = List.filled(64, 'c').join();

/// A platform that is guaranteed not to match the one the test runs on.
UpdatePlatform _otherPlatform() =>
    currentUpdatePlatform() == UpdatePlatform.web
        ? UpdatePlatform.ios
        : UpdatePlatform.web;

/// Serves one fixed cached manifest so the settings update card can be exercised
/// without a full local store.
class _FakeUpdates implements UpdateRepository {
  _FakeUpdates(this.manifest);

  final UpdateManifest? manifest;

  @override
  Future<UpdateManifest?> cached() async => manifest;

  @override
  Future<void> cache(UpdateManifest manifest) async {}
}

UpdateManifest _manifest({
  UpdatePlatform? platform,
  // Far-future for the same reason as update_controller_test: this must stay
  // newer than AppVersion.number across version bumps.
  String version = '99.0.0',
  UpdateSeverity severity = UpdateSeverity.recommended,
}) =>
    UpdateManifest(
      releaseId: 'rel-1',
      version: version,
      buildNumber: 999,
      platform: platform ?? currentUpdatePlatform(),
      channel: currentUpdateChannel(),
      status: ReleaseStatus.active,
      rolloutPercent: 100,
      severity: severity,
      publishedAt: DateTime(2026, 10, 13),
      artifact: ReleaseArtifact(
        reference: 'releases/rms-$version.pkg',
        sizeBytes: 1024,
        sha256: _sha,
      ),
      minSupportedVersion: '0.7.0',
    );

/// An enumerated-empty outbox. Passing null would mean "backlog unreadable"
/// and withhold the install; these cases need "readable and empty".
class _EmptyOutbox implements OutboxAccess {
  @override
  Future<List<OutboxEntry>> all() async => const [];

  @override
  Future<void> save(OutboxEntry entry) async {}
}

AppServices _services(UpdateRepository? updates) => AppServices(
      config: const FirebaseConfig.empty(),
      auth: DemoAuthRepository(),
      firebaseReady: false,
      updates: updates,
      outbox: _EmptyOutbox(),
    );

Future<void> _openSettings(WidgetTester tester, AppServices services) async {
  tester.view.physicalSize = const Size(1600, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(RmsApp(services: services));
  await tester.pumpAndSettle();

  await tester.enterText(find.byType(TextField).at(0), 'ammar@rms.dev');
  await tester.enterText(find.byType(TextField).at(1), 'secret');
  await tester.tap(find.text('دخول'));
  await tester.pumpAndSettle();

  await tester.tap(find.text('الإعدادات'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('settings update card renders the recommended decision',
      (tester) async {
    await _openSettings(tester, _services(_FakeUpdates(_manifest())));

    expect(find.text('التحديثات'), findsOneWidget);
    expect(find.text('مُوصى به'), findsOneWidget);
    expect(find.text('الإصدار المعلن'), findsOneWidget);
    expect(find.text('99.0.0'), findsOneWidget);
    expect(find.textContaining('تحديث مُوصى به'), findsOneWidget);
  });

  testWidgets('settings update card reports a blocked release with its reason',
      (tester) async {
    await _openSettings(
      tester,
      _services(_FakeUpdates(_manifest(platform: _otherPlatform()))),
    );

    // The state card also renders "غير متاح", so scope this to the update Tag.
    expect(find.widgetWithText(Tag, 'غير متاح'), findsOneWidget);
    expect(find.text('سبب عدم الإتاحة'), findsOneWidget);
    expect(find.text('النظام الأساسي غير مطابق'), findsOneWidget);
    expect(find.text('لا يتوفر تحديث لهذا الجهاز'), findsOneWidget);
  });

  testWidgets('settings update card is up to date without a cached manifest',
      (tester) async {
    await _openSettings(tester, _services(_FakeUpdates(null)));

    expect(find.text('محدّث'), findsOneWidget);
    expect(find.text('أنت على أحدث إصدار'), findsOneWidget);
  });
}

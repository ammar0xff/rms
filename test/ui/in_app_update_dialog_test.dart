import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/domain/models/update_manifest.dart';
import 'package:rms/src/features/system/widgets/in_app_update_dialog.dart';

final _testSha = List.filled(64, '0').join();

UpdateManifest _testManifest({
  String version = '0.37.0',
  int buildNumber = 38,
  String releaseNotes = 'تحسينات جذرية في التحديث التلقائي',
  UpdateSeverity severity = UpdateSeverity.optional,
}) {
  return UpdateManifest(
    releaseId: 'rel-test-037',
    version: version,
    buildNumber: buildNumber,
    platform: UpdatePlatform.android,
    channel: UpdateChannel.production,
    status: ReleaseStatus.active,
    severity: severity,
    rolloutPercent: 100,
    publishedAt: DateTime.parse('2026-10-25T12:00:00.000'),
    manifestSchemaVersion: 1,
    artifact: ReleaseArtifact(
      reference: 'https://github.com/ammar-monsef/PIE/releases/download/v0.37.0/app-release.apk',
      sizeBytes: 15 * 1024 * 1024,
      sha256: _testSha,
      signature: 'test-signature',
    ),
    releaseNotes: releaseNotes,
  );
}

void main() {
  group('InAppUpdateDialog Widget Tests', () {
    testWidgets('renders version bump, notes, and install button for optional update', (tester) async {
      final manifest = _testManifest();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => InAppUpdateDialog.show(context, manifest: manifest),
                child: const Text('Show Dialog'),
              ),
            ),
          ),
        ),
      );

      // Open dialog
      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      // Verify dialog header and labels
      expect(find.text('تحديث جديد للنظام'), findsOneWidget);
      expect(find.text('v0.37.0'), findsOneWidget);
      expect(find.text('تحسينات جذرية في التحديث التلقائي'), findsOneWidget);
      expect(find.text('تثبيت التحديث الآن'), findsOneWidget);
      expect(find.text('تأجيل'), findsOneWidget);

      // Dismiss dialog
      await tester.tap(find.text('تأجيل'));
      await tester.pumpAndSettle();
      expect(find.text('تحديث جديد للنظام'), findsNothing);
    });

    testWidgets('shows mandatory warning banner and disables defer button for mandatory update', (tester) async {
      final manifest = _testManifest(severity: UpdateSeverity.mandatory);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => InAppUpdateDialog.show(context, manifest: manifest),
                child: const Text('Show Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      // Verify mandatory notice
      expect(find.text('تحديث إجباري: هذا التحديث إلزامي لمتابعة العمل واستقرار المزامنة.'), findsOneWidget);
      expect(find.text('تأجيل'), findsNothing);
      expect(find.text('تثبيت التحديث الآن'), findsOneWidget);
    });
  });
}

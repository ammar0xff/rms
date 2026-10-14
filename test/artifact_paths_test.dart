import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/data/updates/artifact_paths.dart';
import 'package:rms/src/domain/models/update_manifest.dart';

UpdateManifest _manifest(int buildNumber) => UpdateManifest(
      releaseId: 'android-$buildNumber',
      version: '1.0.0',
      buildNumber: buildNumber,
      platform: UpdatePlatform.android,
      channel: UpdateChannel.production,
      status: ReleaseStatus.active,
      rolloutPercent: 100,
      severity: UpdateSeverity.optional,
      publishedAt: DateTime(2026, 10, 13),
      artifact: const ReleaseArtifact(
        reference: 'releases/android/1.0.0/7/app-release.apk',
        sizeBytes: 1024,
        sha256: 'a' * 64,
      ),
    );

void main() {
  group('artifactFileName', () {
    test('derives a name from the build number', () {
      expect(artifactFileName(_manifest(7)), 'rms-update-7.artifact');
    });

    // The downloader and the installer are built independently and never share
    // state; if these two disagree, the installer opens a file that was never
    // written.
    test('is stable for the same release', () {
      expect(artifactFileName(_manifest(7)), artifactFileName(_manifest(7)));
    });

    test('differs between releases', () {
      expect(artifactFileName(_manifest(7)), isNot(artifactFileName(_manifest(8))));
    });

    test('is a plain file name with no path separators', () {
      final name = artifactFileName(_manifest(42));
      expect(name, isNot(contains('/')));
      expect(name, isNot(contains(r'\')));
      expect(name, endsWith('.artifact'));
    });
  });
}
import '../../domain/models/update_manifest.dart';
import '../../domain/update/artifact_verifier.dart';
import '../../domain/update/download_state.dart';
import '../../domain/update/update_decision.dart';

/// Web stand-in for the artifact downloader.
///
/// Artifact delivery is mobile and desktop only. Web ships through its hosting
/// provider on its own cadence and takes no release artifact, and `dart:io` is
/// unavailable there, so this reports a failure rather than pretending to
/// download something.
///
/// Reporting `failed` is deliberate: the lifecycle coordinator stops before
/// install when the download does not succeed, so a device is never handed an
/// artifact it could not fetch.
class UnsupportedArtifactDownloader implements ArtifactDownloader {
  const UnsupportedArtifactDownloader();

  @override
  Future<DownloadState> start({
    required UpdateManifest manifest,
    required UpdateDecision decision,
  }) async =>
      DownloadState(
        stage: DownloadStage.failed,
        totalBytes: manifest.artifact.sizeBytes,
        error: 'التحديث عبر الحزمة غير مدعوم على منصة الويب',
        endedAt: DateTime.now(),
      );

  @override
  Future<void> cancel() async {}

  @override
  Stream<DownloadState> progress() => const Stream<DownloadState>.empty();
}
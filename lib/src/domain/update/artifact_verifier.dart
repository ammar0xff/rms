import 'package:crypto/crypto.dart';

import '../models/update_manifest.dart';
import 'download_state.dart';
import 'update_decision.dart';

/// The minimal surface an artifact downloader must implement.
///
/// The domain layer only depends on this contract; the platform layer (web/mobile)
/// supplies the actual download mechanism. This keeps the engine pure and
/// trivially testable.
abstract class ArtifactDownloader {
  Future<DownloadState> start({
    required UpdateManifest manifest,
    required UpdateDecision decision,
  });

  Future<void> cancel();

  Stream<DownloadState> progress();
}

/// Verifies a downloaded artifact against the manifest's checksum.
abstract final class ArtifactVerifier {
  /// Returns the verification outcome for the bytes at [path] or the provided
  /// [bytes]. [path] is preferred when available (does not load large blobs into
  /// memory unnecessarily); tests may pass [bytes] directly.
  static Future<ArtifactVerification> verify({
    required UpdateManifest manifest,
    String? path,
    List<int>? bytes,
    ArtifactFileReader? readFile,
  }) async {
    final artifact = manifest.artifact;
    final total = artifact.sizeBytes;

    if (!artifact.hasChecksum) {
      return ArtifactVerification(
        status: ArtifactVerificationStatus.noChecksum,
        downloadedBytes: total,
      );
    }

    final downloadedBytes = await _readBytes(path, bytes, total, readFile);
    if (downloadedBytes == null) {
      return ArtifactVerification(
        status: ArtifactVerificationStatus.notFound,
        downloadedBytes: 0,
      );
    }

    if (downloadedBytes.length != total) {
      final digest = _sha256Hex(downloadedBytes);
      return ArtifactVerification(
        status: ArtifactVerificationStatus.checksumMismatch,
        downloadedBytes: downloadedBytes.length,
        sha256: digest,
      );
    }

    final digest = _sha256Hex(downloadedBytes);
    if (digest.toLowerCase() != artifact.sha256.toLowerCase()) {
      return ArtifactVerification(
        status: ArtifactVerificationStatus.checksumMismatch,
        downloadedBytes: downloadedBytes.length,
        sha256: digest,
      );
    }

    return ArtifactVerification(
      status: ArtifactVerificationStatus.verified,
      downloadedBytes: downloadedBytes.length,
      sha256: digest,
    );
  }

  static Future<List<int>?> _readBytes(
    String? path,
    List<int>? bytes,
    int total,
    ArtifactFileReader? readFile,
  ) async {
    if (bytes != null) return bytes;
    if (path == null || path.isEmpty) return null;
    // Reading a file needs dart:io, which this layer deliberately does not
    // import, so the platform layer supplies the reader. There used to be a
    // stub here whose methods threw; the catch below turned that into a null,
    // and every real download was therefore reported as notFound. Nothing
    // noticed because the unit tests all passed bytes and never went near it.
    final read = readFile;
    if (read == null) return null;
    try {
      final data = await read(path);
      if (data.isEmpty && total > 0) return null;
      return data;
    } catch (_) {
      return null;
    }
  }
}

/// Reads a file into memory, supplied by the platform layer.
///
/// The domain layer cannot read files itself without importing `dart:io`, so
/// `ArtifactVerifier.verify` takes the reader as an argument. Passing none
/// alongside a [path] yields `notFound` rather than an unverified success.
typedef ArtifactFileReader = Future<List<int>> Function(String path);

/// The SHA-256 of [bytes], lowercase hex.
///
/// Delegates to `package:crypto`, which is pure Dart — no `dart:io`, no Flutter
/// bindings — so the domain layer stays trivially testable while the hashing
/// itself is a vetted implementation rather than a hand-rolled one.
///
/// This was previously a 65-line SHA-256 written out by hand, with the test
/// copying it a third time. That arrangement checked the copy against itself
/// rather than against a known-good digest, on the one code path that decides
/// whether a downloaded APK is the one that was published.
String _sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

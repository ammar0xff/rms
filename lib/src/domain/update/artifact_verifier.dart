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
  }) async {
    final artifact = manifest.artifact;
    final total = artifact.sizeBytes;

    if (!artifact.hasChecksum) {
      return ArtifactVerification(
        status: ArtifactVerificationStatus.noChecksum,
        downloadedBytes: total,
      );
    }

    final downloadedBytes = await _readBytes(path, bytes, total);
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
  ) async {
    if (bytes != null) return bytes;
    if (path == null || path.isEmpty) return null;
    try {
      final file = _File(path);
      final length = await file.length();
      if (length < 0) return null;
      if (length == 0 && total > 0) return null;
      return await file.readAsBytes();
    } catch (_) {
      return null;
    }
  }
}

/// Minimal file abstraction so ArtifactVerifier can be pure-tested without
/// importing flutter/foundation or dart:io in test contexts.
/// The real implementation wraps `dart:io`'s File; in unit tests this class is
/// not used directly (bytes are passed in).
class _File {
  _File(this.path);

  final String path;

  Future<int> length() => throw UnimplementedError();
  Future<List<int>> readAsBytes() => throw UnimplementedError();
}

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

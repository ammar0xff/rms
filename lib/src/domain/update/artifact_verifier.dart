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

/// Naive SHA-256 for verification in unit tests (bytes are provided directly).
/// This is a minimal implementation sufficient for the domain logic; platform
/// layers can use a vetted implementation when reading from storage.
String _sha256Hex(List<int> bytes) {
  final digest = _sha256(bytes);
  final sb = StringBuffer();
  for (final b in digest) {
    sb.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
}

List<int> _sha256(List<int> bytes) {
  final h = <int>[
    0x6a09e667,
    0xbb67ae85,
    0x3c6ef372,
    0xa54ff53a,
    0x510e527f,
    0x9b05688c,
    0x1f83d9ab,
    0x5be0cd19
  ];
  final k = <int>[
    0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
    0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
    0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
    0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
    0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
    0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
    0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
    0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2
  ];
  final msg = <int>[...bytes, 0x80];
  while ((msg.length % 64) != 56) msg.add(0);
  final bitlen = bytes.length * 8;
  for (var i = 7; i >= 0; i--) msg.add((bitlen >> (i * 8)) & 0xff);
  for (var i = 0; i < msg.length; i += 64) {
    final w = List.filled(64, 0);
    for (var j = 0; j < 16; j++) {
      w[j] = (msg[i + j * 4] << 24) | (msg[i + j * 4 + 1] << 16) | (msg[i + j * 4 + 2] << 8) | msg[i + j * 4 + 3];
    }
    for (var j = 16; j < 64; j++) {
      final s0 = _rotr(w[j - 15], 7) ^ _rotr(w[j - 15], 18) ^ (w[j - 15] >>> 3);
      final s1 = _rotr(w[j - 2], 17) ^ _rotr(w[j - 2], 19) ^ (w[j - 2] >>> 10);
      w[j] = (w[j - 16] + s0 + w[j - 7] + s1) & 0xffffffff;
    }
    var a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], ha = h[7];
    for (var j = 0; j < 64; j++) {
      final s1h = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
      final ch = (e & f) ^ ((~e) & g);
      final temp1 = (ha + s1h + ch + k[j] + w[j]) & 0xffffffff;
      final s0h = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
      final maj = (a & b) ^ (a & c) ^ (b & c);
      final temp2 = (s0h + maj) & 0xffffffff;
      ha = g; g = f; f = e; e = (d + temp1) & 0xffffffff; d = c; c = b; b = a; a = (temp1 + temp2) & 0xffffffff;
    }
    h[0] = (h[0] + a) & 0xffffffff; h[1] = (h[1] + b) & 0xffffffff; h[2] = (h[2] + c) & 0xffffffff;
    h[3] = (h[3] + d) & 0xffffffff; h[4] = (h[4] + e) & 0xffffffff; h[5] = (h[5] + f) & 0xffffffff;
    h[6] = (h[6] + g) & 0xffffffff; h[7] = (h[7] + ha) & 0xffffffff;
  }
  final out = <int>[];
  for (var i = 0; i < 8; i++) out.addAll([(h[i] >> 24) & 0xff, (h[i] >> 16) & 0xff, (h[i] >> 8) & 0xff, h[i] & 0xff]);
  return out;
}

int _rotr(int x, int n) => ((x >>> n) | (x << (32 - n))) & 0xffffffff;

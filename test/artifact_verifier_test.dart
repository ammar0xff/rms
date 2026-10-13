import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/domain/models/update_manifest.dart';
import 'package:rms/src/domain/update/artifact_verifier.dart';
import 'package:rms/src/domain/update/download_state.dart';

final _shaEmpty = _shaHex(''.codeUnits);
final _shaHello = _shaHex('hello'.codeUnits);

String _shaHex(List<int> bytes) {
  final digest = _sha(bytes);
  final sb = StringBuffer();
  for (final b in digest) {
    sb.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
}

List<int> _sha(List<int> bytes) {
  // Reuse the same implementation logic (copy of the one in verifier is small).
  final h = <int>[0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19];
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
    for (var j = 0; j < 16; j++) w[j] = (msg[i + j * 4] << 24) | (msg[i + j * 4 + 1] << 16) | (msg[i + j * 4 + 2] << 8) | msg[i + j * 4 + 3];
    for (var j = 16; j < 64; j++) {
      final s0 = ((w[j - 15] >>> 7) ^ (w[j - 15] >>> 18) ^ (w[j - 15] >>> 3)) & 0xffffffff;
      final s1 = ((w[j - 2] >>> 17) ^ (w[j - 2] >>> 19) ^ (w[j - 2] >>> 10)) & 0xffffffff;
      w[j] = (w[j - 16] + s0 + w[j - 7] + s1) & 0xffffffff;
    }
    var a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], ha = h[7];
    for (var j = 0; j < 64; j++) {
      final s1h = ((e >>> 6) ^ (e >>> 11) ^ (e >>> 25)) & 0xffffffff;
      final ch = ((e & f) ^ ((~e) & g)) & 0xffffffff;
      final temp1 = (ha + s1h + ch + k[j] + w[j]) & 0xffffffff;
      final s0h = ((a >>> 2) ^ (a >>> 13) ^ (a >>> 22)) & 0xffffffff;
      final maj = ((a & b) ^ (a & c) ^ (b & c)) & 0xffffffff;
      final temp2 = (s0h + maj) & 0xffffffff;
      ha = g; g = f; f = e; e = (d + temp1) & 0xffffffff; d = c; c = b; b = a; a = (temp1 + temp2) & 0xffffffff;
    }
    for (var t = 0; t < 8; t++) h[t] = (h[t] + [a,b,c,d,e,f,g,ha][t]) & 0xffffffff;
  }
  final out = <int>[];
  for (var i = 0; i < 8; i++) out.addAll([(h[i] >> 24) & 0xff, (h[i] >> 16) & 0xff, (h[i] >> 8) & 0xff, h[i] & 0xff]);
  return out;
}

UpdateManifest _manifest({
  String sha256 = '',
  int sizeBytes = 0,
  String reference = 'releases/test.bin',
}) =>
    UpdateManifest(
      releaseId: 'rel-test',
      version: '1.0.0',
      buildNumber: 1,
      platform: UpdatePlatform.web,
      channel: UpdateChannel.production,
      status: ReleaseStatus.active,
      severity: UpdateSeverity.optional,
      rolloutPercent: 100,
      publishedAt: DateTime(2026, 10, 13),
      artifact: ReleaseArtifact(
        reference: reference,
        sizeBytes: sizeBytes,
        sha256: sha256,
      ),
    );

void main() {
  group('ArtifactVerification', () {
    test('returns noChecksum when the manifest lacks a checksum', () async {
      final result = await ArtifactVerifier.verify(
        manifest: _manifest(sha256: 'not64'),
        bytes: [],
      );
      expect(result.status, ArtifactVerificationStatus.noChecksum);
      expect(result.isOk, isFalse);
    });

    test('returns notFound when no bytes or path are provided', () async {
      final result = await ArtifactVerifier.verify(
        manifest: _manifest(sha256: _shaEmpty, sizeBytes: 0),
      );
      expect(result.status, ArtifactVerificationStatus.notFound);
    });

    test('verifies a correct checksum for bytes', () async {
      final data = 'hello'.codeUnits;
      final result = await ArtifactVerifier.verify(
        manifest: _manifest(sha256: _shaHello, sizeBytes: data.length),
        bytes: data,
      );
      expect(result.status, ArtifactVerificationStatus.verified);
      expect(result.isOk, isTrue);
      expect(result.downloadedBytes, data.length);
    });

    test('detects a checksum mismatch', () async {
      final data = 'hello'.codeUnits;
      final result = await ArtifactVerifier.verify(
        manifest: _manifest(sha256: _shaEmpty, sizeBytes: data.length),
        bytes: data,
      );
      expect(result.status, ArtifactVerificationStatus.checksumMismatch);
    });

    test('detects size mismatch before or alongside checksum', () async {
      final data = 'hello'.codeUnits;
      final result = await ArtifactVerifier.verify(
        manifest: _manifest(sha256: _shaHello, sizeBytes: data.length + 5),
        bytes: data,
      );
      expect(result.status, ArtifactVerificationStatus.checksumMismatch);
      expect(result.downloadedBytes, data.length);
    });
  });

  group('DownloadState', () {
    test('tracks active and terminal stages', () {
      const active = DownloadState(
        stage: DownloadStage.downloading,
        totalBytes: 100,
        downloadedBytes: 10,
        progress: 0.1,
      );
      const terminal = DownloadState(
        stage: DownloadStage.completed,
        totalBytes: 100,
        downloadedBytes: 100,
        progress: 1.0,
      );
      expect(active.isActive, isTrue);
      expect(active.isTerminal, isFalse);
      expect(terminal.isActive, isFalse);
      expect(terminal.isTerminal, isTrue);
    });
  });
}

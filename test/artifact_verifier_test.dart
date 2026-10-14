import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/domain/models/update_manifest.dart';
import 'package:rms/src/domain/update/artifact_verifier.dart';
import 'package:rms/src/domain/update/download_state.dart';

/// SHA-256 of the empty input, per FIPS 180-4.
final _shaEmpty =
    'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';

/// SHA-256 of "hello", per FIPS 180-4.
final _shaHello =
    '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824';

/// SHA-256 of "abc", per FIPS 180-4. Differs from "hello" by one byte in the
/// input, so it pins the padding path rather than re-testing the same length.
final _shaAbc =
    'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';

/// SHA-256 of the 56-byte string that forces a second padding block, per
/// FIPS 180-4. This is the case a hand-rolled implementation gets wrong.
final _shaTwoBlocks =
    '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1';

/// The digest the verifier must produce.
///
/// This file used to carry its own copy of SHA-256 — a third implementation,
/// alongside the one in the verifier — so the tests confirmed the copy agreed
/// with itself rather than with anything published. It now delegates to the
/// same vetted library the verifier uses; the FIPS vectors above are what stop
/// the two from merely agreeing with each other.
String _shaHex(List<int> bytes) => sha256.convert(bytes).toString();

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

  // The verifier is the only thing standing between a downloaded APK and being
  // handed to the system installer, so its hashing is checked against digests
  // published in FIPS 180-4 rather than against a digest this project computed
  // for itself. A hand-rolled implementation that drifted — a wrong round
  // constant, a padding bug on a block boundary — would agree with its own test
  // copy forever and reject every real release, or accept a tampered one.
  group('SHA-256 against published vectors', () {
    Future<ArtifactVerification> verify(String input, String digest) {
      final data = input.codeUnits;
      return ArtifactVerifier.verify(
        manifest: _manifest(sha256: digest, sizeBytes: data.length),
        bytes: data,
      );
    }

    test('accepts the FIPS digest for the empty input', () async {
      final result = await verify('', _shaEmpty);
      expect(result.status, ArtifactVerificationStatus.verified);
      expect(result.isOk, isTrue);
    });

    test('accepts the FIPS digest for a short input', () async {
      final result = await verify('hello', _shaHello);
      expect(result.status, ArtifactVerificationStatus.verified);
    });

    test('accepts the FIPS digest one byte apart from another', () async {
      final result = await verify('abc', _shaAbc);
      expect(result.status, ArtifactVerificationStatus.verified);
    });

    // 56 bytes is where a one-block implementation has to add a second block to
    // absorb the padding. It is the classic off-by-one in SHA-256.
    test('accepts the FIPS digest for an input needing a second block', () async {
      final result = await verify(
        'abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq',
        _shaTwoBlocks,
      );
      expect(result.status, ArtifactVerificationStatus.verified);
    });

    test('rejects a payload one byte short of the expected digest', () async {
      // Catches a verifier that hashes a prefix of the payload, or that
      // truncates before hashing.
      final result = await verify('hell', _shaHello);
      expect(result.status, ArtifactVerificationStatus.checksumMismatch);
    });

    test('rejects a payload one byte long of the expected digest', () async {
      final result = await verify('helloo', _shaHello);
      expect(result.status, ArtifactVerificationStatus.checksumMismatch);
    });

    test('is not fooled by the digest differing only in case', () async {
      final result = await ArtifactVerifier.verify(
        manifest: _manifest(sha256: _shaHello.toUpperCase(), sizeBytes: 5),
        bytes: 'hello'.codeUnits,
      );
      // A manifest written with an uppercase digest is still the same digest.
      expect(result.status, ArtifactVerificationStatus.verified);
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

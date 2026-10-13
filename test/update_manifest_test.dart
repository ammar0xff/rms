import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/domain/models/update_manifest.dart';

final _sha = List.filled(64, 'a').join();

Map<String, Object?> _artifact({Object? sha256}) => {
      'reference': 'releases/web/1.2.0',
      'sizeBytes': 2048,
      'sha256': sha256 ?? _sha,
      'signature': 'sig',
    };

Map<String, Object?> _record({
  Object? releaseId = 'rel-1',
  Object? version = '1.2.0',
  Object? buildNumber = 12,
  Object? platform = 'web',
  Object? channel = 'production',
  Object? status = 'active',
  Object? severity = 'optional',
  Object? rolloutPercent = 100,
  Object? publishedAt = '2026-10-13T12:00:00.000',
  Object? manifestSchemaVersion = 1,
  Object? artifact,
  Object? minSupportedVersion,
  Object? architecture,
}) =>
    {
      'releaseId': releaseId,
      'version': version,
      'buildNumber': buildNumber,
      'platform': platform,
      'channel': channel,
      'status': status,
      'severity': severity,
      'rolloutPercent': rolloutPercent,
      'publishedAt': publishedAt,
      'artifact': artifact ?? _artifact(),
      'manifestSchemaVersion': manifestSchemaVersion,
      if (minSupportedVersion != null) 'minSupportedVersion': minSupportedVersion,
      if (architecture != null) 'architecture': architecture,
    };

void main() {
  group('UpdateManifest.parse', () {
    test('parses a well-formed document and round-trips through a record', () {
      final result = UpdateManifest.parse(
        _record(
          minSupportedVersion: '1.0.0',
          architecture: 'wasm',
        )..addAll({
            'minBackendVersion': '2026.01.01',
            'maxBackendVersion': '2026.12.31',
            'localSchemaMin': 4,
            'localSchemaMax': 6,
            'requiredMigrationVersion': 6,
            'releaseNotes': 'إصلاحات',
            'expiresAt': '2027-01-01T00:00:00.000',
            'forceAfter': '2026-11-01T00:00:00.000',
            'rollbackTargetVersion': '1.1.0',
            'targetBranchIds': ['BR-01', 'BR-02'],
            'targetDeviceGroups': ['terminals'],
          }),
      );

      expect(result.isSuccess, isTrue);
      final manifest = result.manifest!;
      expect(manifest.releaseId, 'rel-1');
      expect(manifest.version, '1.2.0');
      expect(manifest.platform, UpdatePlatform.web);
      expect(manifest.channel, UpdateChannel.production);
      expect(manifest.status, ReleaseStatus.active);
      expect(manifest.severity, UpdateSeverity.optional);
      expect(manifest.architecture, 'wasm');
      expect(manifest.minSupportedVersion, '1.0.0');
      expect(manifest.minBackendVersion, '2026.01.01');
      expect(manifest.localSchemaMin, 4);
      expect(manifest.requiredMigrationVersion, 6);
      expect(manifest.targetBranchIds, ['BR-01', 'BR-02']);
      expect(manifest.artifact.hasChecksum, isTrue);
      expect(manifest.parsedVersion!.major, 1);

      final roundTripped = UpdateManifest.parse(manifest.toRecord()).manifest!;
      expect(roundTripped.releaseId, manifest.releaseId);
      expect(roundTripped.version, manifest.version);
      expect(roundTripped.artifact.sha256, manifest.artifact.sha256);
      expect(roundTripped.targetBranchIds, manifest.targetBranchIds);
      expect(roundTripped.expiresAt, manifest.expiresAt);
    });

    test('rejects a document missing a required field', () {
      final result = UpdateManifest.parse(_record(releaseId: ''));
      expect(result.isSuccess, isFalse);
      expect(result.error, ManifestParseError.missingField);

      expect(
        UpdateManifest.parse(_record(buildNumber: null)).error,
        ManifestParseError.missingField,
      );
      expect(
        UpdateManifest.parse(_record(publishedAt: null)).error,
        ManifestParseError.missingField,
      );
      expect(
        UpdateManifest.parse(_record(manifestSchemaVersion: null)).error,
        ManifestParseError.missingField,
      );
    });

    test('rejects malformed versions', () {
      expect(
        UpdateManifest.parse(_record(version: '1.2')).error,
        ManifestParseError.malformedVersion,
      );
      expect(
        UpdateManifest.parse(_record(minSupportedVersion: 'one')).error,
        ManifestParseError.malformedVersion,
      );
    });

    test('rejects unknown enum values', () {
      expect(
        UpdateManifest.parse(_record(platform: 'watchos')).error,
        ManifestParseError.unknownPlatform,
      );
      expect(
        UpdateManifest.parse(_record(channel: 'canary')).error,
        ManifestParseError.unknownChannel,
      );
      expect(
        UpdateManifest.parse(_record(status: 'shelved')).error,
        ManifestParseError.unknownStatus,
      );
      expect(
        UpdateManifest.parse(_record(severity: 'critical')).error,
        ManifestParseError.unknownSeverity,
      );
    });

    test('rejects an out-of-range rollout percentage', () {
      expect(
        UpdateManifest.parse(_record(rolloutPercent: 150)).error,
        ManifestParseError.invalidRollout,
      );
      expect(
        UpdateManifest.parse(_record(rolloutPercent: -1)).error,
        ManifestParseError.invalidRollout,
      );
      expect(
        UpdateManifest.parse(_record(rolloutPercent: '50')).error,
        ManifestParseError.invalidRollout,
      );
    });

    test('rejects a malformed artifact', () {
      expect(
        UpdateManifest.parse(_record(artifact: 'not-a-map')).error,
        ManifestParseError.invalidArtifact,
      );
      expect(
        UpdateManifest.parse(_record(artifact: _artifact(sha256: ''))).error,
        ManifestParseError.invalidArtifact,
      );
      expect(
        UpdateManifest.parse(_record(artifact: {
          'reference': '',
          'sizeBytes': 1,
          'sha256': _sha,
        })).error,
        ManifestParseError.invalidArtifact,
      );
    });

    test('only accepts a full-length checksum as verifiable', () {
      expect(
        const ReleaseArtifact(reference: 'x', sizeBytes: 1, sha256: 'abc')
            .hasChecksum,
        isFalse,
      );
      expect(
        ReleaseArtifact(reference: 'x', sizeBytes: 1, sha256: _sha).hasChecksum,
        isTrue,
      );
    });
  });
}

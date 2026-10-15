import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/domain/models/update_manifest.dart';
import 'package:rms/src/domain/update/update_decision.dart';

final _now = DateTime(2026, 10, 13, 14);
final _sha = List.filled(64, 'b').join();

UpdateManifest _manifest({
  String version = '1.2.0',
  UpdatePlatform platform = UpdatePlatform.web,
  UpdateChannel channel = UpdateChannel.production,
  ReleaseStatus status = ReleaseStatus.active,
  UpdateSeverity severity = UpdateSeverity.optional,
  int rolloutPercent = 100,
  String architecture = '',
  String minSupportedVersion = '0.0.0',
  String? minBackendVersion,
  String? maxBackendVersion,
  int? localSchemaMin,
  int? localSchemaMax,
  int? requiredMigrationVersion,
  DateTime? expiresAt,
  DateTime? forceAfter,
  List<String> targetBranchIds = const [],
  List<String> targetDeviceGroups = const [],
  int manifestSchemaVersion = UpdateManifest.schemaVersion,
}) =>
    UpdateManifest(
      releaseId: 'rel-1',
      version: version,
      buildNumber: 2,
      platform: platform,
      architecture: architecture,
      channel: channel,
      status: status,
      rolloutPercent: rolloutPercent,
      severity: severity,
      publishedAt: _now,
      artifact: ReleaseArtifact(
        reference: 'releases/web/$version',
        sizeBytes: 1024,
        sha256: _sha,
      ),
      minSupportedVersion: minSupportedVersion,
      minBackendVersion: minBackendVersion,
      maxBackendVersion: maxBackendVersion,
      localSchemaMin: localSchemaMin,
      localSchemaMax: localSchemaMax,
      requiredMigrationVersion: requiredMigrationVersion,
      expiresAt: expiresAt,
      forceAfter: forceAfter,
      targetBranchIds: targetBranchIds,
      targetDeviceGroups: targetDeviceGroups,
      manifestSchemaVersion: manifestSchemaVersion,
    );

UpdateContext _context({
  String installedVersion = '1.0.0',
  UpdatePlatform platform = UpdatePlatform.web,
  UpdateChannel channel = UpdateChannel.production,
  String architecture = '',
  String backendVersion = '2026.10.11',
  int localSchemaVersion = 5,
  String branchId = 'BR-01',
  String deviceGroup = 'terminals',
  String cohortSeed = 'device-1',
  DateTime? now,
}) =>
    UpdateContext(
      installedVersion: installedVersion,
      platform: platform,
      channel: channel,
      architecture: architecture,
      backendVersion: backendVersion,
      localSchemaVersion: localSchemaVersion,
      branchId: branchId,
      deviceGroup: deviceGroup,
      cohortSeed: cohortSeed,
      now: now ?? _now,
    );

void main() {
  group('UpdateDecisionEngine.decide', () {
    test('is up to date when nothing was published', () {
      final decision = UpdateDecisionEngine.decide(
        manifest: null,
        context: _context(),
      );
      expect(decision.status, UpdateDecisionStatus.upToDate);
      expect(decision.isUpdate, isFalse);
      expect(decision.isBlocked, isFalse);
      expect(decision.release, isNull);
    });

    test('offers an eligible optional release and exposes its bucket', () {
      final decision = UpdateDecisionEngine.decide(
        manifest: _manifest(),
        context: _context(),
      );
      expect(decision.status, UpdateDecisionStatus.optional);
      expect(decision.isUpdate, isTrue);
      expect(decision.blockReason, isNull);
      expect(decision.bucket, isNotNull);
      expect(decision.canVerifyArtifact, isTrue);
    });

    test('reports recommended and mandatory severities', () {
      expect(
        UpdateDecisionEngine.decide(
          manifest: _manifest(severity: UpdateSeverity.recommended),
          context: _context(),
        ).status,
        UpdateDecisionStatus.recommended,
      );
      expect(
        UpdateDecisionEngine.decide(
          manifest: _manifest(severity: UpdateSeverity.mandatory),
          context: _context(),
        ).status,
        UpdateDecisionStatus.mandatory,
      );
    });

    test('a passed forceAfter makes an optional release mandatory', () {
      final decision = UpdateDecisionEngine.decide(
        manifest: _manifest(forceAfter: _now.subtract(const Duration(days: 1))),
        context: _context(),
      );
      expect(decision.status, UpdateDecisionStatus.mandatory);
      expect(decision.forced, isTrue);

      final pending = UpdateDecisionEngine.decide(
        manifest: _manifest(forceAfter: _now.add(const Duration(days: 1))),
        context: _context(),
      );
      expect(pending.status, UpdateDecisionStatus.optional);
      expect(pending.forced, isFalse);
    });

    test('blocks a newer manifest schema the client does not understand', () {
      final decision = UpdateDecisionEngine.decide(
        manifest: _manifest(manifestSchemaVersion: 2),
        context: _context(),
      );
      expect(decision.isBlocked, isTrue);
      expect(decision.blockReason, UpdateBlockReason.unsupportedManifestSchema);
    });

    test('blocks a platform or architecture mismatch', () {
      expect(
        UpdateDecisionEngine.decide(
          manifest: _manifest(platform: UpdatePlatform.android),
          context: _context(),
        ).blockReason,
        UpdateBlockReason.platformMismatch,
      );
      expect(
        UpdateDecisionEngine.decide(
          manifest: _manifest(architecture: 'arm64'),
          context: _context(architecture: 'x64'),
        ).blockReason,
        UpdateBlockReason.architectureMismatch,
      );
      // An unknown architecture on either side is not a mismatch.
      expect(
        UpdateDecisionEngine.decide(
          manifest: _manifest(architecture: 'arm64'),
          context: _context(),
        ).isUpdate,
        isTrue,
      );
    });

    test('blocks a channel mismatch or a non-deliverable release', () {
      expect(
        UpdateDecisionEngine.decide(
          manifest: _manifest(channel: UpdateChannel.beta),
          context: _context(),
        ).blockReason,
        UpdateBlockReason.channelMismatch,
      );
      expect(
        UpdateDecisionEngine.decide(
          manifest: _manifest(status: ReleaseStatus.paused),
          context: _context(),
        ).blockReason,
        UpdateBlockReason.notDeliverable,
      );
      expect(
        UpdateDecisionEngine.decide(
          manifest: _manifest(status: ReleaseStatus.revoked),
          context: _context(),
        ).blockReason,
        UpdateBlockReason.notDeliverable,
      );
    });

    test('blocks an expired release', () {
      final decision = UpdateDecisionEngine.decide(
        manifest: _manifest(expiresAt: _now),
        context: _context(),
      );
      expect(decision.blockReason, UpdateBlockReason.expired);

      final fresh = UpdateDecisionEngine.decide(
        manifest: _manifest(expiresAt: _now.add(const Duration(days: 1))),
        context: _context(),
      );
      expect(fresh.isUpdate, isTrue);
    });

    test('blocks when the offer is not newer than the installed version', () {
      expect(
        UpdateDecisionEngine.decide(
          manifest: _manifest(version: '1.0.0'),
          context: _context(),
        ).blockReason,
        UpdateBlockReason.alreadyInstalled,
      );
      expect(
        UpdateDecisionEngine.decide(
          manifest: _manifest(version: '0.9.0'),
          context: _context(),
        ).blockReason,
        UpdateBlockReason.versionNotNewer,
      );
      expect(
        UpdateDecisionEngine.decide(
          manifest: _manifest(version: '1.2.0', minSupportedVersion: '1.1.0'),
          context: _context(installedVersion: '1.0.0'),
        ).blockReason,
        // Staged updates get their own reason: the release IS newer, the
        // device is just too old to take it directly.
        UpdateBlockReason.belowMinSupported,
      );
    });

    test('blocks a branch or device group outside the rollout scope', () {
      expect(
        UpdateDecisionEngine.decide(
          manifest: _manifest(targetBranchIds: ['BR-99']),
          context: _context(),
        ).blockReason,
        UpdateBlockReason.branchExcluded,
      );
      expect(
        UpdateDecisionEngine.decide(
          manifest: _manifest(targetDeviceGroups: ['qa']),
          context: _context(),
        ).blockReason,
        UpdateBlockReason.groupExcluded,
      );
      expect(
        UpdateDecisionEngine.decide(
          manifest: _manifest(
            targetBranchIds: ['BR-01'],
            targetDeviceGroups: ['terminals'],
          ),
          context: _context(),
        ).isUpdate,
        isTrue,
      );
    });

    test('gates a partial rollout on the deterministic cohort bucket', () {
      // A paused rollout (0%) never offers the release.
      expect(
        UpdateDecisionEngine.decide(
          manifest: _manifest(rolloutPercent: 0),
          context: _context(),
        ).blockReason,
        UpdateBlockReason.rolloutExcluded,
      );

      // Without a cohort seed only a full rollout is offered.
      expect(
        UpdateDecisionEngine.decide(
          manifest: _manifest(rolloutPercent: 50),
          context: _context(cohortSeed: ''),
        ).blockReason,
        UpdateBlockReason.rolloutExcluded,
      );
      expect(
        UpdateDecisionEngine.decide(
          manifest: _manifest(rolloutPercent: 100),
          context: _context(cohortSeed: ''),
        ).isUpdate,
        isTrue,
      );

      // With a seed, membership is stable and deterministic.
      String? included;
      String? excluded;
      for (var i = 0; i < 200 && (included == null || excluded == null); i++) {
        final seed = 'device-$i';
        final decision = UpdateDecisionEngine.decide(
          manifest: _manifest(rolloutPercent: 50),
          context: _context(cohortSeed: seed),
        );
        if (decision.isUpdate) {
          included ??= seed;
        } else {
          expect(decision.blockReason, UpdateBlockReason.rolloutExcluded);
          excluded ??= seed;
        }
      }
      expect(included, isNotNull);
      expect(excluded, isNotNull);

      final repeated = UpdateDecisionEngine.decide(
        manifest: _manifest(rolloutPercent: 50),
        context: _context(cohortSeed: included!),
      );
      expect(repeated.isUpdate, isTrue);
      expect(repeated.bucket, lessThan(50));
    });

    test('gates backend compatibility in both directions', () {
      expect(
        UpdateDecisionEngine.decide(
          manifest: _manifest(minBackendVersion: '2027.01.01'),
          context: _context(),
        ).blockReason,
        UpdateBlockReason.backendIncompatible,
      );
      expect(
        UpdateDecisionEngine.decide(
          manifest: _manifest(maxBackendVersion: '2026.01.01'),
          context: _context(),
        ).blockReason,
        UpdateBlockReason.backendIncompatible,
      );
      // An unknown backend version skips the check: nothing in the app reports
      // one, so blocking on it would brick delivery the moment any release
      // published bounds. The bounds still gate devices that know better.
      expect(
        UpdateDecisionEngine.decide(
          manifest: _manifest(minBackendVersion: '2026.01.01'),
          context: _context(backendVersion: 'unknown'),
        ).isUpdate,
        isTrue,
      );
      expect(
        UpdateDecisionEngine.decide(
          manifest: _manifest(
            minBackendVersion: '2026.01.01',
            maxBackendVersion: '2026.12.31',
          ),
          context: _context(),
        ).isUpdate,
        isTrue,
      );
    });

    test('gates the local schema range and reports required migrations', () {
      expect(
        UpdateDecisionEngine.decide(
          manifest: _manifest(localSchemaMin: 6),
          context: _context(localSchemaVersion: 5),
        ).blockReason,
        UpdateBlockReason.schemaIncompatible,
      );
      expect(
        UpdateDecisionEngine.decide(
          manifest: _manifest(localSchemaMax: 4),
          context: _context(localSchemaVersion: 5),
        ).blockReason,
        UpdateBlockReason.schemaIncompatible,
      );

      final ahead = UpdateDecisionEngine.decide(
        manifest: _manifest(requiredMigrationVersion: 6),
        context: _context(localSchemaVersion: 5),
      );
      expect(ahead.isUpdate, isTrue);
      expect(ahead.requiresMigration, isTrue);

      final current = UpdateDecisionEngine.decide(
        manifest: _manifest(requiredMigrationVersion: 5),
        context: _context(localSchemaVersion: 5),
      );
      expect(current.requiresMigration, isFalse);
    });

    test('is a pure function of its inputs', () {
      final manifest = _manifest(rolloutPercent: 40);
      final context = _context(cohortSeed: 'terminal-7');
      final first = UpdateDecisionEngine.decide(
        manifest: manifest,
        context: context,
      );
      final second = UpdateDecisionEngine.decide(
        manifest: manifest,
        context: context,
      );
      expect(first.status, second.status);
      expect(first.bucket, second.bucket);
      expect(first.blockReason, second.blockReason);
    });
  });
}

import 'semantic_version.dart';

/// The platform a release artifact targets.
///
/// Delivery is platform-specific: web updates ship through Hosting, mobile
/// through the store/MDM, and desktop through a signed installer. The client
/// therefore only ever accepts a manifest published for its own platform.
enum UpdatePlatform {
  android('أندرويد'),
  ios('iOS'),
  windows('ويندوز'),
  macos('macOS'),
  linux('لينكس'),
  web('الويب');

  const UpdatePlatform(this.label);

  final String label;

  static UpdatePlatform? tryParse(String? value) {
    for (final platform in values) {
      if (platform.name == value) return platform;
    }
    return null;
  }
}

/// The channel a manifest is published to.
enum UpdateChannel {
  development('تطوير'),
  beta('تجريبي'),
  production('إنتاج');

  const UpdateChannel(this.label);

  final String label;

  static UpdateChannel? tryParse(String? value) {
    for (final channel in values) {
      if (channel.name == value) return channel;
    }
    return null;
  }
}

/// The lifecycle state of a published release.
///
/// Only [active] releases are offered to clients; [paused] and [revoked] remain
/// visible in the manager view but must never be delivered.
enum ReleaseStatus {
  draft('مسودة'),
  staged('مُهيّأ'),
  active('نشط'),
  paused('متوقف مؤقتًا'),
  revoked('ملغى');

  const ReleaseStatus(this.label);

  final String label;

  static ReleaseStatus? tryParse(String? value) {
    for (final status in values) {
      if (status.name == value) return status;
    }
    return null;
  }

  bool get isDeliverable => this == active;
}

/// How strongly the client should push a release to the user.
enum UpdateSeverity {
  optional('اختياري'),
  recommended('مُوصى به'),
  mandatory('إلزامي');

  const UpdateSeverity(this.label);

  final String label;

  static UpdateSeverity? tryParse(String? value) {
    for (final severity in values) {
      if (severity.name == value) return severity;
    }
    return null;
  }
}

/// The downloadable artifact for a release.
///
/// [reference] is either a Cloud Storage path or an approved distribution URL.
/// The SHA-256 checksum is mandatory so a partial or tampered file is rejected
/// before it ever reaches the installer.
class ReleaseArtifact {
  const ReleaseArtifact({
    required this.reference,
    required this.sizeBytes,
    required this.sha256,
    this.signature = '',
    this.expiresAt,
  });

  final String reference;
  final int sizeBytes;
  final String sha256;
  final String signature;
  final DateTime? expiresAt;

  static final RegExp _hex = RegExp(r'^[0-9a-fA-F]{64}$');

  /// True when the artifact carries a full 64-hex-digit SHA-256 checksum.
  bool get hasChecksum => _hex.hasMatch(sha256);

  Map<String, Object?> toRecord() => {
        'reference': reference,
        'sizeBytes': sizeBytes,
        'sha256': sha256,
        'signature': signature,
        'expiresAt': expiresAt?.toIso8601String(),
      };

  /// Parses a stored artifact, or returns null when a required field is missing
  /// or malformed.
  static ReleaseArtifact? tryFromRecord(Map<String, Object?> record) {
    final reference = record['reference'];
    final size = record['sizeBytes'];
    final sha = record['sha256'];
    if (reference is! String || reference.isEmpty) return null;
    if (size is! int || size < 0) return null;
    if (sha is! String || sha.isEmpty) return null;
    final expires = record['expiresAt'];
    return ReleaseArtifact(
      reference: reference,
      sizeBytes: size,
      sha256: sha,
      signature: record['signature'] as String? ?? '',
      expiresAt: expires is String ? DateTime.tryParse(expires) : null,
    );
  }
}

/// Why a raw manifest document was rejected during parsing.
enum ManifestParseError {
  missingField('حقل مطلوب مفقود'),
  malformedVersion('إصدار غير صالح'),
  unknownPlatform('نظام أساسي غير معروف'),
  unknownChannel('قناة غير معروفة'),
  unknownStatus('حالة إصدار غير معروفة'),
  unknownSeverity('درجة تحديث غير معروفة'),
  invalidRollout('نسبة نشر غير صالحة'),
  invalidArtifact('حزمة غير صالحة');

  const ManifestParseError(this.label);

  final String label;
}

/// The outcome of parsing a raw release-manifest document.
///
/// Parsing is deliberately total: a malformed document returns a
/// [ManifestParseError] instead of throwing or producing a half-populated
/// manifest that could be partially honoured.
class ManifestParse {
  const ManifestParse._(this.manifest, this.error);

  const ManifestParse.success(UpdateManifest manifest) : this._(manifest, null);

  const ManifestParse.failure(ManifestParseError error) : this._(null, error);

  final UpdateManifest? manifest;
  final ManifestParseError? error;

  bool get isSuccess => manifest != null;
}

/// The v1.2 Firebase-delivered release-manifest contract.
///
/// This is the artifact-delivery manifest: one immutable release per platform,
/// channel and version, describing the artifact to install, the rollout cohort
/// and the compatibility gates. The cached capability manifest that carries
/// feature flags is a separate, lighter document, and it never gates artifact
/// delivery. Manifests are parsed defensively so a malformed or newer-schema
/// document is rejected rather than guessed at.
class UpdateManifest {
  const UpdateManifest({
    required this.releaseId,
    required this.version,
    required this.buildNumber,
    required this.platform,
    required this.channel,
    required this.status,
    required this.rolloutPercent,
    required this.severity,
    required this.publishedAt,
    required this.artifact,
    this.architecture = '',
    this.minSupportedVersion = '0.0.0',
    this.minBackendVersion,
    this.maxBackendVersion,
    this.localSchemaMin,
    this.localSchemaMax,
    this.requiredMigrationVersion,
    this.releaseNotes = '',
    this.expiresAt,
    this.forceAfter,
    this.rollbackTargetVersion,
    this.targetBranchIds = const [],
    this.targetDeviceGroups = const [],
    this.manifestSchemaVersion = schemaVersion,
  });

  /// The manifest schema this client understands. Documents advertising a
  /// higher schema version are rejected rather than guessed at.
  static const int schemaVersion = 1;

  final String releaseId;
  final String version;
  final int buildNumber;
  final UpdatePlatform platform;
  final String architecture;
  final UpdateChannel channel;
  final ReleaseStatus status;
  final int rolloutPercent;
  final UpdateSeverity severity;
  final DateTime publishedAt;
  final ReleaseArtifact artifact;

  final String minSupportedVersion;
  final String? minBackendVersion;
  final String? maxBackendVersion;
  final int? localSchemaMin;
  final int? localSchemaMax;
  final int? requiredMigrationVersion;

  final String releaseNotes;
  final DateTime? expiresAt;
  final DateTime? forceAfter;
  final String? rollbackTargetVersion;
  final List<String> targetBranchIds;
  final List<String> targetDeviceGroups;
  final int manifestSchemaVersion;

  SemanticVersion? get parsedVersion => SemanticVersion.tryParse(version);

  SemanticVersion? get parsedMinSupported =>
      SemanticVersion.tryParse(minSupportedVersion);

  bool isExpiredAt(DateTime now) =>
      expiresAt != null && !now.isBefore(expiresAt!);

  Map<String, Object?> toRecord() => {
        'releaseId': releaseId,
        'version': version,
        'buildNumber': buildNumber,
        'platform': platform.name,
        'architecture': architecture,
        'channel': channel.name,
        'status': status.name,
        'rolloutPercent': rolloutPercent,
        'severity': severity.name,
        'publishedAt': publishedAt.toIso8601String(),
        'artifact': artifact.toRecord(),
        'minSupportedVersion': minSupportedVersion,
        'minBackendVersion': minBackendVersion,
        'maxBackendVersion': maxBackendVersion,
        'localSchemaMin': localSchemaMin,
        'localSchemaMax': localSchemaMax,
        'requiredMigrationVersion': requiredMigrationVersion,
        'releaseNotes': releaseNotes,
        'expiresAt': expiresAt?.toIso8601String(),
        'forceAfter': forceAfter?.toIso8601String(),
        'rollbackTargetVersion': rollbackTargetVersion,
        'targetBranchIds': targetBranchIds,
        'targetDeviceGroups': targetDeviceGroups,
        'manifestSchemaVersion': manifestSchemaVersion,
      };

  /// Defensively parses a raw document.
  ///
  /// Structural problems are reported as a [ManifestParseError]; eligibility
  /// against a specific device (platform, expiry, compatibility, rollout) is
  /// left to the decision engine, which has the device context.
  static ManifestParse parse(Map<String, Object?> record) {
    final schema = record['manifestSchemaVersion'];
    if (schema is! int) {
      return const ManifestParse.failure(ManifestParseError.missingField);
    }

    final releaseId = record['releaseId'];
    if (releaseId is! String || releaseId.isEmpty) {
      return const ManifestParse.failure(ManifestParseError.missingField);
    }

    final build = record['buildNumber'];
    if (build is! int) {
      return const ManifestParse.failure(ManifestParseError.missingField);
    }

    final version = SemanticVersion.tryParse(record['version'] as String?);
    if (version == null) {
      return const ManifestParse.failure(ManifestParseError.malformedVersion);
    }

    final minSupportedRaw = record['minSupportedVersion'] as String?;
    if (minSupportedRaw != null &&
        SemanticVersion.tryParse(minSupportedRaw) == null) {
      return const ManifestParse.failure(ManifestParseError.malformedVersion);
    }

    final platform = UpdatePlatform.tryParse(record['platform'] as String?);
    if (platform == null) {
      return const ManifestParse.failure(ManifestParseError.unknownPlatform);
    }

    final channel = UpdateChannel.tryParse(record['channel'] as String?);
    if (channel == null) {
      return const ManifestParse.failure(ManifestParseError.unknownChannel);
    }

    final status = ReleaseStatus.tryParse(record['status'] as String?);
    if (status == null) {
      return const ManifestParse.failure(ManifestParseError.unknownStatus);
    }

    final severity = UpdateSeverity.tryParse(record['severity'] as String?);
    if (severity == null) {
      return const ManifestParse.failure(ManifestParseError.unknownSeverity);
    }

    final rollout = record['rolloutPercent'];
    if (rollout is! int || rollout < 0 || rollout > 100) {
      return const ManifestParse.failure(ManifestParseError.invalidRollout);
    }

    final publishedAt = _date(record['publishedAt']);
    if (publishedAt == null) {
      return const ManifestParse.failure(ManifestParseError.missingField);
    }

    final artifactRecord = record['artifact'];
    if (artifactRecord is! Map) {
      return const ManifestParse.failure(ManifestParseError.invalidArtifact);
    }
    final artifact =
        ReleaseArtifact.tryFromRecord(Map<String, Object?>.from(artifactRecord));
    if (artifact == null) {
      return const ManifestParse.failure(ManifestParseError.invalidArtifact);
    }

    return ManifestParse.success(
      UpdateManifest(
        releaseId: releaseId,
        version: version.toString(),
        buildNumber: build,
        platform: platform,
        architecture: record['architecture'] as String? ?? '',
        channel: channel,
        status: status,
        rolloutPercent: rollout,
        severity: severity,
        publishedAt: publishedAt,
        artifact: artifact,
        minSupportedVersion: minSupportedRaw ?? '0.0.0',
        minBackendVersion: record['minBackendVersion'] as String?,
        maxBackendVersion: record['maxBackendVersion'] as String?,
        localSchemaMin: record['localSchemaMin'] as int?,
        localSchemaMax: record['localSchemaMax'] as int?,
        requiredMigrationVersion: record['requiredMigrationVersion'] as int?,
        releaseNotes: record['releaseNotes'] as String? ?? '',
        expiresAt: _date(record['expiresAt']),
        forceAfter: _date(record['forceAfter']),
        rollbackTargetVersion: record['rollbackTargetVersion'] as String?,
        targetBranchIds: _strings(record['targetBranchIds']),
        targetDeviceGroups: _strings(record['targetDeviceGroups']),
        manifestSchemaVersion: schema,
      ),
    );
  }

  static DateTime? _date(Object? value) {
    if (value is! String) return null;
    return DateTime.tryParse(value);
  }

  static List<String> _strings(Object? value) {
    if (value is! List) return const [];
    return [
      for (final item in value)
        if (item is String) item,
    ];
  }
}

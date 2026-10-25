import '../models/semantic_version.dart';
import '../models/update_manifest.dart';

/// The action the client should take for a cached release.
enum UpdateDecisionStatus {
  upToDate('أنت على أحدث إصدار'),
  optional('تحديث اختياري متاح'),
  recommended('تحديث مُوصى به'),
  mandatory('تحديث إلزامي'),
  ineligible('مفيش تحديث لهذا الجهاز');

  const UpdateDecisionStatus(this.label);

  final String label;

  bool get isUpdate =>
      this == optional || this == recommended || this == mandatory;
}

/// Why a release was withheld from this device.
///
/// A release is only offered when *every* gate passes; the first failed gate is
/// reported so the client can explain the outcome without exposing internals.
enum UpdateBlockReason {
  unsupportedManifestSchema('مخطط بيان أحدث من دعم العميل'),
  platformMismatch('النظام الأساسي غير مطابق'),
  architectureMismatch('المعمارية غير مطابقة'),
  channelMismatch('قناة الإصدار غير مطابقة'),
  notDeliverable('الإصدار غير قابل للتوزيع'),
  expired('انتهت صلاحية الإصدار'),
  alreadyInstalled('الإصدار مثبّت بالفعل'),
  versionNotNewer('الإصدار ليس أحدث من المثبّت'),
  belowMinSupported('الإصدار الحالي أقدم من الحد الأدنى المدعوم'),
  branchExcluded('الفرع خارج نطاق النشر'),
  groupExcluded('مجموعة الأجهزة خارج نطاق النشر'),
  rolloutExcluded('الجهاز خارج نسبة النشر'),
  backendIncompatible('توافق السيرفر غير مطابق'),
  schemaIncompatible('توافق المخطط المحلي غير مطابق');

  const UpdateBlockReason(this.label);

  final String label;
}

/// The device facts a decision is evaluated against.
class UpdateContext {
  const UpdateContext({
    required this.installedVersion,
    required this.platform,
    required this.channel,
    required this.now,
    this.installedBuild = 0,
    this.architecture = '',
    this.backendVersion = '',
    this.localSchemaVersion = 0,
    this.branchId = '',
    this.deviceGroup = '',
    this.cohortSeed = '',
  });

  final String installedVersion;
  final int installedBuild;
  final UpdatePlatform platform;
  final String architecture;
  final UpdateChannel channel;
  final DateTime now;
  final String backendVersion;
  final int localSchemaVersion;
  final String branchId;
  final String deviceGroup;

  /// A stable per-device (or per-branch) identifier used for rollout bucketing.
  /// When empty, the device only joins releases published at 100%.
  final String cohortSeed;
}

/// The outcome of [UpdateDecisionEngine.decide].
class UpdateDecision {
  const UpdateDecision({
    required this.status,
    this.release,
    this.blockReason,
    this.bucket,
    this.requiresMigration = false,
    this.forced = false,
  });

  final UpdateDecisionStatus status;

  /// The release the decision refers to, or null when nothing was published.
  final UpdateManifest? release;

  /// Set only for [UpdateDecisionStatus.ineligible].
  final UpdateBlockReason? blockReason;

  /// The device's deterministic rollout bucket in 0..99, when one was computed.
  final int? bucket;

  /// True when installing the release will advance the local schema.
  final bool requiresMigration;

  /// True when a `forceAfter` deadline has passed and the release is mandatory.
  final bool forced;

  bool get isUpdate => status.isUpdate;

  bool get isBlocked => status == UpdateDecisionStatus.ineligible;

  /// Whether the artifact carries a checksum the client could verify.
  bool get canVerifyArtifact => release?.artifact.hasChecksum ?? false;
}

/// Pure, offline-safe client update decision.
///
/// The decision is a function of the cached manifest and the device context, so
/// two terminals with the same inputs reach the same outcome. It never performs
/// I/O or installation; it only classifies the release as up-to-date, optional,
/// recommended, mandatory, or ineligible (with a reason). The backend remains
/// authoritative: this engine gates what the client will *offer*, not what the
/// server may publish.
abstract final class UpdateDecisionEngine {
  /// Number of rollout buckets. A device is eligible when its bucket is below
  /// the release's [UpdateManifest.rolloutPercent].
  static const int buckets = 100;

  static UpdateDecision decide({
    required UpdateManifest? manifest,
    required UpdateContext context,
    int maxSupportedManifestSchema = UpdateManifest.schemaVersion,
  }) {
    final release = manifest;
    if (release == null) {
      return const UpdateDecision(status: UpdateDecisionStatus.upToDate);
    }

    UpdateDecision block(UpdateBlockReason reason, {int? bucket}) =>
        UpdateDecision(
          status: UpdateDecisionStatus.ineligible,
          release: release,
          blockReason: reason,
          bucket: bucket,
        );

    if (release.manifestSchemaVersion > maxSupportedManifestSchema) {
      return block(UpdateBlockReason.unsupportedManifestSchema);
    }
    if (release.platform != context.platform) {
      return block(UpdateBlockReason.platformMismatch);
    }
    if (release.architecture.isNotEmpty &&
        context.architecture.isNotEmpty &&
        release.architecture != context.architecture) {
      return block(UpdateBlockReason.architectureMismatch);
    }
    if (release.channel != context.channel) {
      return block(UpdateBlockReason.channelMismatch);
    }
    if (!release.status.isDeliverable) {
      return block(UpdateBlockReason.notDeliverable);
    }
    if (release.isExpiredAt(context.now)) {
      return block(UpdateBlockReason.expired);
    }

    final offered = release.parsedVersion;
    final installed = SemanticVersion.tryParse(context.installedVersion);
    if (offered == null || installed == null) {
      return block(UpdateBlockReason.versionNotNewer);
    }
    if (offered == installed) {
      if (context.installedBuild > 0 &&
          release.buildNumber > context.installedBuild) {
        // Same semantic version but newer build number: eligible.
      } else {
        return block(UpdateBlockReason.alreadyInstalled);
      }
    }
    if (offered < installed) {
      return block(UpdateBlockReason.versionNotNewer);
    }
    final minSupported = release.parsedMinSupported;
    if (minSupported != null && installed < minSupported) {
      // Staged updates: a device older than the minimum cannot jump straight
      // to this release — it must come up through an intermediate one. This is
      // a deliberate gate, not a version comparison, so it gets its own
      // reason instead of masquerading as "not newer".
      return block(UpdateBlockReason.belowMinSupported);
    }

    if (release.targetBranchIds.isNotEmpty &&
        !release.targetBranchIds.contains(context.branchId)) {
      return block(UpdateBlockReason.branchExcluded);
    }
    if (release.targetDeviceGroups.isNotEmpty &&
        !release.targetDeviceGroups.contains(context.deviceGroup)) {
      return block(UpdateBlockReason.groupExcluded);
    }

    final bucket = _rolloutBucket(release, context);
    if (bucket == null) {
      return block(UpdateBlockReason.rolloutExcluded);
    }

    // Backend bounds are only evaluated when the device actually knows its
    // backend version. Nothing in the app reports one today, so an unknown
    // backend must skip the check: blocking on an unevaluable condition would
    // brick delivery fleet-wide the moment any release published bounds.
    final backend = SemanticVersion.tryParse(context.backendVersion);
    final minBackend = SemanticVersion.tryParse(release.minBackendVersion);
    if (release.minBackendVersion != null &&
        backend != null &&
        (minBackend == null || backend < minBackend)) {
      return block(UpdateBlockReason.backendIncompatible, bucket: bucket);
    }
    final maxBackend = SemanticVersion.tryParse(release.maxBackendVersion);
    if (release.maxBackendVersion != null &&
        backend != null &&
        (maxBackend == null || backend > maxBackend)) {
      return block(UpdateBlockReason.backendIncompatible, bucket: bucket);
    }

    if (release.localSchemaMin != null &&
        context.localSchemaVersion < release.localSchemaMin!) {
      return block(UpdateBlockReason.schemaIncompatible, bucket: bucket);
    }
    if (release.localSchemaMax != null &&
        context.localSchemaVersion > release.localSchemaMax!) {
      return block(UpdateBlockReason.schemaIncompatible, bucket: bucket);
    }

    final requiresMigration = release.requiredMigrationVersion != null &&
        release.requiredMigrationVersion! > context.localSchemaVersion;
    final forced = release.forceAfter != null &&
        !context.now.isBefore(release.forceAfter!);
    final mandatory =
        release.severity == UpdateSeverity.mandatory || forced;

    return UpdateDecision(
      status: mandatory
          ? UpdateDecisionStatus.mandatory
          : release.severity == UpdateSeverity.recommended
              ? UpdateDecisionStatus.recommended
              : UpdateDecisionStatus.optional,
      release: release,
      bucket: bucket,
      requiresMigration: requiresMigration,
      forced: forced,
    );
  }

  /// The device's rollout bucket, or null when it must not receive the release
  /// (paused rollout, or no cohort seed while the release is staged).
  static int? _rolloutBucket(UpdateManifest release, UpdateContext context) {
    if (release.rolloutPercent >= buckets) return _bucket(context.cohortSeed);
    if (release.rolloutPercent <= 0) return null;
    if (context.cohortSeed.isEmpty) return null;
    final bucket = _bucket(context.cohortSeed);
    return bucket < release.rolloutPercent ? bucket : null;
  }

  /// Deterministic 0..99 bucket for [seed] (Jenkins one-at-a-time hash).
  ///
  /// Every step is masked to 32 bits, so the result is identical on the VM and
  /// on the web (where integers are doubles and would otherwise lose precision).
  static int _bucket(String seed) {
    var hash = 0;
    for (final unit in seed.codeUnits) {
      hash = (hash + unit) & 0xffffffff;
      hash = (hash + (hash << 10)) & 0xffffffff;
      hash ^= hash >> 6;
    }
    hash = (hash + (hash << 3)) & 0xffffffff;
    hash ^= hash >> 11;
    hash = (hash + (hash << 15)) & 0xffffffff;
    return hash % buckets;
  }
}

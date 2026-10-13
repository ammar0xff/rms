/// The lifecycle state of the device's update attempt.
enum UpdateLifecycleState {
  idle('لا يوجد تحديث جاري'),
  readyToInstall('جاهز للتثبيت'),
  installing('جاري التثبيت'),
  migrating('جاري الترحيل'),
  healthCheck('فحص ما بعد التحديث'),
  rebooting('إعادة التشغيل'),
  completed('اكتمل التحديث'),
  failed('فشل التحديث'),
  rolledBack('تم التراجع');

  const UpdateLifecycleState(this.label);

  final String label;
}

/// The result of a health-check after applying an update.
enum UpdateHealthStatus {
  pending('قيد الفحص'),
  passed('نجح الفحص'),
  failed('فشل الفحص'),
  inconclusive('غير حاسم');

  const UpdateHealthStatus(this.label);

  final String label;
}

/// The reason an update attempt ended.
enum UpdateFailureReason {
  none(''),
  downloadFailed('فشل التنزيل'),
  verificationFailed('فشل التحقق'),
  installFailed('فشل التثبيت'),
  migrationFailed('فشل الترحيل'),
  healthCheckFailed('فشل فحص ما بعد التحديث'),
  rollbackFailed('فشل التراجع'),
  userCancelled('أُلغي من المستخدم');

  const UpdateFailureReason(this.label);

  final String label;
}

/// Tracks the device's current update status (AC-31+).
class DeviceUpdateStatus {
  const DeviceUpdateStatus({
    required this.state,
    this.statusAt,
    this.releaseId = '',
    this.version = '',
    this.buildNumber = 0,
    this.progress = 0.0,
    this.health = UpdateHealthStatus.pending,
    this.failureReason = UpdateFailureReason.none,
    this.errorMessage = '',
    this.rollbackTargetVersion = '',
    this.requiresRollback = false,
    this.lastAppliedAt,
  });

  final UpdateLifecycleState state;
  final DateTime? statusAt;
  final String releaseId;
  final String version;
  final int buildNumber;
  final double progress;
  final UpdateHealthStatus health;
  final UpdateFailureReason failureReason;
  final String errorMessage;
  final String rollbackTargetVersion;
  final bool requiresRollback;
  final DateTime? lastAppliedAt;

  bool get isActive =>
      state == UpdateLifecycleState.installing ||
      state == UpdateLifecycleState.migrating ||
      state == UpdateLifecycleState.healthCheck ||
      state == UpdateLifecycleState.rebooting;

  bool get isTerminal =>
      state == UpdateLifecycleState.completed ||
      state == UpdateLifecycleState.failed ||
      state == UpdateLifecycleState.rolledBack;

  DeviceUpdateStatus copyWith({
    UpdateLifecycleState? state,
    DateTime? statusAt,
    String? releaseId,
    String? version,
    int? buildNumber,
    double? progress,
    UpdateHealthStatus? health,
    UpdateFailureReason? failureReason,
    String? errorMessage,
    String? rollbackTargetVersion,
    bool? requiresRollback,
    DateTime? lastAppliedAt,
  }) =>
      DeviceUpdateStatus(
        state: state ?? this.state,
        statusAt: statusAt ?? this.statusAt,
        releaseId: releaseId ?? this.releaseId,
        version: version ?? this.version,
        buildNumber: buildNumber ?? this.buildNumber,
        progress: progress ?? this.progress,
        health: health ?? this.health,
        failureReason: failureReason ?? this.failureReason,
        errorMessage: errorMessage ?? this.errorMessage,
        rollbackTargetVersion: rollbackTargetVersion ?? this.rollbackTargetVersion,
        requiresRollback: requiresRollback ?? this.requiresRollback,
        lastAppliedAt: lastAppliedAt ?? this.lastAppliedAt,
      );

  Map<String, Object?> toRecord() => {
        'state': state.name,
        'statusAt': statusAt?.toIso8601String(),
        'releaseId': releaseId,
        'version': version,
        'buildNumber': buildNumber,
        'progress': progress,
        'health': health.name,
        'failureReason': failureReason.name,
        'errorMessage': errorMessage,
        'rollbackTargetVersion': rollbackTargetVersion,
        'requiresRollback': requiresRollback,
        'lastAppliedAt': lastAppliedAt?.toIso8601String(),
      };

  /// Restores a persisted status, or null when the record is malformed.
  ///
  /// Parsing is deliberately total: an unknown lifecycle state or health value
  /// yields null rather than a half-populated status, so a corrupt row is
  /// treated as "no status recorded" instead of being partially honoured.
  static DeviceUpdateStatus? tryFromRecord(Map<String, Object?> record) {
    final stateName = record['state'];
    if (stateName is! String) return null;
    final state = UpdateLifecycleState.values
        .where((e) => e.name == stateName)
        .firstOrNull;
    if (state == null) return null;

    final healthName = record['health'];
    final health = healthName is String
        ? UpdateHealthStatus.values.where((e) => e.name == healthName).firstOrNull
        : null;
    if (health == null) return null;

    final reasonName = record['failureReason'];
    final reason = reasonName is String
        ? UpdateFailureReason.values
            .where((e) => e.name == reasonName)
            .firstOrNull
        : null;
    if (reason == null) return null;

    DateTime? at(String key) {
      final value = record[key];
      if (value is! String) return null;
      return DateTime.tryParse(value);
    }

    final build = record['buildNumber'];
    final progress = record['progress'];
    return DeviceUpdateStatus(
      state: state,
      statusAt: at('statusAt'),
      releaseId: record['releaseId'] as String? ?? '',
      version: record['version'] as String? ?? '',
      buildNumber: build is int ? build : 0,
      progress: progress is num ? progress.toDouble() : 0.0,
      health: health,
      failureReason: reason,
      errorMessage: record['errorMessage'] as String? ?? '',
      rollbackTargetVersion: record['rollbackTargetVersion'] as String? ?? '',
      requiresRollback: record['requiresRollback'] == true,
      lastAppliedAt: at('lastAppliedAt'),
    );
  }
}

/// The desired behaviour of automatic updates on a device (AC-41).
enum UpdatePolicyMode {
  auto('تلقائي'),
  prompt('يطلب تأكيد'),
  defer('يؤجل'),
  disabled('معطل');

  const UpdatePolicyMode(this.label);

  final String label;
}

/// A local policy that controls how aggressively the app offers/install updates.
class UpdatePolicy {
  const UpdatePolicy({
    required this.mode,
    this.allowBeta = false,
    this.allowWifiOnly = true,
    this.deferUntil,
    this.maxDeferCount = 3,
    this.acknowledgeStuckWork = false,
  });

  final UpdatePolicyMode mode;
  final bool allowBeta;
  final bool allowWifiOnly;
  final DateTime? deferUntil;
  final int maxDeferCount;
  final bool acknowledgeStuckWork;

  UpdatePolicy copyWith({
    UpdatePolicyMode? mode,
    bool? allowBeta,
    bool? allowWifiOnly,
    DateTime? deferUntil,
    int? maxDeferCount,
    bool? acknowledgeStuckWork,
  }) =>
      UpdatePolicy(
        mode: mode ?? this.mode,
        allowBeta: allowBeta ?? this.allowBeta,
        allowWifiOnly: allowWifiOnly ?? this.allowWifiOnly,
        deferUntil: deferUntil ?? this.deferUntil,
        maxDeferCount: maxDeferCount ?? this.maxDeferCount,
        acknowledgeStuckWork: acknowledgeStuckWork ?? this.acknowledgeStuckWork,
      );
}

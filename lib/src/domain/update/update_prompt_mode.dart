/// How insistently the client should ask for the update.
enum UpdatePromptMode {
  /// Nothing to offer: up to date, ineligible, or no release published.
  none('لا يوجد تحديث'),

  /// A mandatory release. The operator cannot carry on working until it is
  /// applied, so this is shown as a screen rather than a dismissible prompt.
  blocking('تحديث إلزامي'),

  /// An optional or recommended release. Offered, but never forced.
  dismissible('تحديث متاح'),

  /// An update is being applied right now.
  working('جارٍ التطبيق'),

  /// The last attempt finished, but failed.
  failed('فشل التحديث'),

  /// The last attempt finished successfully.
  completed('اكتمل التحديث');

  const UpdatePromptMode(this.label);

  final String label;

  bool get isTerminal => this == completed || this == failed;

  bool get isBusy => this == working;

  /// True when the prompt must not be dismissed: either an update is in flight,
  /// the release is mandatory, or the last attempt failed and needs attention.
  bool get isEnforced =>
      this == blocking || this == working || this == failed;
}
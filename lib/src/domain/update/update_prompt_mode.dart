/// How insistently the client should ask for the update.
enum UpdatePromptMode {
  /// Nothing to offer: up to date, ineligible, or no release published.
  none('مفيش تحديث'),

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

  /// True when the prompt must not be dismissed: an update in flight, or a
  /// mandatory release the operator has not yet applied.
  ///
  /// A *failed* attempt is deliberately dismissible. Dismissing it changes
  /// nothing about what was installed — the attempt already ended — and a
  /// blocking screen with a disabled button and no exit traps the operator on
  /// the exact screen that should help them recover.
  bool get isEnforced => this == blocking || this == working;
}
import 'local_work_snapshot.dart';

/// An operator's decision to proceed with an update while local work is stuck.
///
/// A stuck record is one a sync can never resolve on its own: the backend
/// rejected it as conflicting, parked it for a human, or refused it outright.
/// Those records are still local work, so AC-35 keeps them out of the install
/// path. An acknowledgement is the explicit, attributed escape hatch — and it
/// is deliberately narrow:
///
/// * It is scoped to a **count**, not a blanket yes. When new stuck work
///   appears the acknowledgement stops covering it, so an operator cannot
///   silently bless records they never saw.
/// * It covers a **subset**: acknowledging five and later having three left is
///   still covered, because those three were among the five reviewed.
/// * It never covers unsynced work. [covers] refuses outright when
///   [LocalWorkSnapshot.unsynced] is non-zero; that work *can* still reach the
///   backend, so there is nothing legitimate to waive.
class UpdateAcknowledgement {
  const UpdateAcknowledgement({
    required this.stuckCount,
    required this.acknowledgedAt,
    this.acknowledgedBy = '',
    this.note = '',
  });

  /// How many stuck records the operator reviewed and accepted.
  final int stuckCount;

  /// When the acknowledgement was made.
  final DateTime acknowledgedAt;

  /// Who made it, for the audit trail.
  final String acknowledgedBy;

  /// Free-text reason, carried into the audit event.
  final String note;

  /// Whether this acknowledgement still applies to [work].
  ///
  /// False when nothing is stuck (there is nothing to waive), when unsynced work
  /// exists, or when the stuck count has grown past what was reviewed.
  bool covers(LocalWorkSnapshot work) {
    if (work.hasUnsynced) return false;
    if (!work.hasStuck) return false;
    return work.stuck <= stuckCount;
  }

  Map<String, Object?> toRecord() => {
    'stuckCount': stuckCount,
    'acknowledgedAt': acknowledgedAt.toIso8601String(),
    'acknowledgedBy': acknowledgedBy,
    'note': note,
  };

  /// Parses a stored acknowledgement, or null when malformed.
  static UpdateAcknowledgement? tryFromRecord(Map<String, Object?> record) {
    final count = record['stuckCount'];
    final at = record['acknowledgedAt'];
    if (count is! int || count < 0) return null;
    if (at is! String) return null;
    final parsed = DateTime.tryParse(at);
    if (parsed == null) return null;
    // Tested rather than cast: these two are free-text, so a row written by an
    // older or partial version could hold a number here. A cast would throw and
    // take the whole sync down, where this must degrade to "no acknowledgement"
    // so the gate falls back to demanding a fresh sign-off.
    final by = record['acknowledgedBy'];
    final note = record['note'];
    return UpdateAcknowledgement(
      stuckCount: count,
      acknowledgedAt: parsed,
      acknowledgedBy: by is String ? by : '',
      note: note is String ? note : '',
    );
  }
}

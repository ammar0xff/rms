/// Records an audit event for the update lifecycle (AC-39).
enum ReleaseAuditEventType {
  discovered('تم اكتشاف تحديث'),
  decided('تم اتخاذ قرار'),
  downloadStarted('بدأ التنزيل'),
  downloadCompleted('اكتمل التنزيل'),
  verificationPassed('نجح التحقق'),
  verificationFailed('فشل التحقق'),
  installStarted('بدأ التثبيت'),
  installCompleted('اكتمل التثبيت'),
  migrationStarted('بدأ الترحيل'),
  migrationCompleted('اكتمل الترحيل'),
  healthCheckPassed('نجح فحص ما بعد التحديث'),
  healthCheckFailed('فشل فحص ما بعد التحديث'),
  acknowledged('تم الإقرار'),
  rolledBack('تم التراجع'),
  failed('فشل'),
  updateWithheld('أُجّل التثبيت لحماية الأعمال المحلية');

  const ReleaseAuditEventType(this.label);

  final String label;
}

/// An immutable audit record for an update event.
class ReleaseAuditEvent {
  const ReleaseAuditEvent({
    required this.eventId,
    required this.releaseId,
    required this.occurredAt,
    required this.eventType,
    this.deviceId = '',
    this.deviceGroup = '',
    this.outcome = '',
    this.reason = '',
    this.actorId = '',
    this.metadata = const {},
  });

  final String eventId;
  final String releaseId;
  final DateTime occurredAt;
  final ReleaseAuditEventType eventType;
  final String deviceId;
  final String deviceGroup;
  final String outcome;
  final String reason;
  final String actorId;
  final Map<String, Object?> metadata;

  Map<String, Object?> toRecord() => {
        'eventId': eventId,
        'releaseId': releaseId,
        'occurredAt': occurredAt.toIso8601String(),
        'eventType': eventType.name,
        'deviceId': deviceId,
        'deviceGroup': deviceGroup,
        'outcome': outcome,
        'reason': reason,
        'actorId': actorId,
        'metadata': metadata,
      };

  static ReleaseAuditEvent? tryFromRecord(Map<String, Object?> record) {
    final eventId = record['eventId'];
    final releaseId = record['releaseId'];
    final occurredAt = record['occurredAt'];
    final eventTypeStr = record['eventType'];
    if (eventId is! String || eventId.isEmpty) return null;
    if (releaseId is! String || releaseId.isEmpty) return null;
    if (occurredAt is! String) return null;
    if (eventTypeStr is! String || eventTypeStr.isEmpty) return null;
    final occurred = DateTime.tryParse(occurredAt);
    if (occurred == null) return null;
    final eventType = ReleaseAuditEventType.values
        .where((e) => e.name == eventTypeStr)
        .firstOrNull;
    if (eventType == null) return null;
    return ReleaseAuditEvent(
      eventId: eventId,
      releaseId: releaseId,
      occurredAt: occurred,
      eventType: eventType,
      deviceId: record['deviceId'] as String? ?? '',
      deviceGroup: record['deviceGroup'] as String? ?? '',
      outcome: record['outcome'] as String? ?? '',
      reason: record['reason'] as String? ?? '',
      actorId: record['actorId'] as String? ?? '',
      metadata: record['metadata'] is Map
          ? Map<String, Object?>.from(record['metadata'] as Map)
          : const {},
    );
  }
}

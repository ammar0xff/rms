import 'outbox_status.dart';

class OutboxEntry {
  const OutboxEntry({
    required this.operationId,
    required this.entityType,
    required this.entityId,
    required this.operationType,
    required this.payload,
    required this.schemaVersion,
    required this.idempotencyKey,
    required this.createdAt,
    this.attemptCount = 0,
    this.lastAttemptAt,
    this.lastError,
    this.syncStatus = OutboxStatus.pending,
  });

  final String operationId;
  final String entityType;
  final String entityId;
  final String operationType;
  final Map<String, dynamic> payload;
  final int schemaVersion;
  final String idempotencyKey;
  final DateTime createdAt;
  final int attemptCount;
  final DateTime? lastAttemptAt;
  final String? lastError;
  final OutboxStatus syncStatus;

  OutboxEntry copyWith({
    OutboxStatus? syncStatus,
    int? attemptCount,
    DateTime? lastAttemptAt,
    String? lastError,
    bool clearLastError = false,
    Map<String, dynamic>? payload,
  }) {
    return OutboxEntry(
      operationId: operationId,
      entityType: entityType,
      entityId: entityId,
      operationType: operationType,
      payload: payload ?? this.payload,
      schemaVersion: schemaVersion,
      idempotencyKey: idempotencyKey,
      createdAt: createdAt,
      attemptCount: attemptCount ?? this.attemptCount,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      lastError: clearLastError ? null : (lastError ?? this.lastError),
      syncStatus: syncStatus ?? this.syncStatus,
    );
  }

  Map<String, Object?> toRecord() => {
        'operationId': operationId,
        'entityType': entityType,
        'entityId': entityId,
        'operationType': operationType,
        'payload': payload,
        'schemaVersion': schemaVersion,
        'idempotencyKey': idempotencyKey,
        'createdAt': createdAt.toIso8601String(),
        'attemptCount': attemptCount,
        'lastAttemptAt': lastAttemptAt?.toIso8601String(),
        'lastError': lastError,
        'syncStatus': syncStatus.name,
      };

  static OutboxEntry fromRecord(Map<String, Object?> record) => OutboxEntry(
        operationId: record['operationId'] as String,
        entityType: record['entityType'] as String,
        entityId: record['entityId'] as String,
        operationType: record['operationType'] as String,
        payload: Map<String, dynamic>.from(record['payload'] as Map),
        schemaVersion: record['schemaVersion'] as int,
        idempotencyKey: record['idempotencyKey'] as String,
        createdAt: DateTime.parse(record['createdAt'] as String),
        // No dependencyIds: the key was removed (stored by nothing, read by
        // nothing). Old rows still carrying it parse fine — unknown keys are
        // simply never read.
        attemptCount: record['attemptCount'] as int? ?? 0,
        lastAttemptAt: record['lastAttemptAt'] == null
            ? null
            : DateTime.parse(record['lastAttemptAt'] as String),
        lastError: record['lastError'] as String?,
        syncStatus: OutboxStatus.values.byName(record['syncStatus'] as String),
      );
}

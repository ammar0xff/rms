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
    this.dependencyIds = const [],
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
  final List<String> dependencyIds;
  final int attemptCount;
  final DateTime? lastAttemptAt;
  final String? lastError;
  final OutboxStatus syncStatus;

  OutboxEntry copyWith({
    OutboxStatus? syncStatus,
    int? attemptCount,
    DateTime? lastAttemptAt,
    String? lastError,
  }) {
    return OutboxEntry(
      operationId: operationId,
      entityType: entityType,
      entityId: entityId,
      operationType: operationType,
      payload: payload,
      schemaVersion: schemaVersion,
      idempotencyKey: idempotencyKey,
      createdAt: createdAt,
      dependencyIds: dependencyIds,
      attemptCount: attemptCount ?? this.attemptCount,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      lastError: lastError ?? this.lastError,
      syncStatus: syncStatus ?? this.syncStatus,
    );
  }
}

enum OutboxStatus {
  pending,
  inProgress,
  synced,
  retryableFailure,
  conflict,
  requiresUserAction,
  permanentlyRejected,
}

enum SyncStatus {
  localOnly,
  pendingSync,
  synced,
  conflict,
}

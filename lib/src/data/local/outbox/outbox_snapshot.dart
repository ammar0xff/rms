import '../../../domain/update/update_readiness.dart';
import 'outbox_status.dart';
import 'outbox_store.dart';

/// Summarises the transactional outbox into the counts the update readiness gate
/// needs. Returns an empty snapshot when there is no store.
Future<LocalWorkSnapshot> loadLocalWorkSnapshot(
  OutboxStore? outbox, {
  required bool online,
}) async {
  if (outbox == null) return LocalWorkSnapshot(online: online);
  var pending = 0;
  var inProgress = 0;
  var retryable = 0;
  var conflict = 0;
  var userAction = 0;
  var rejected = 0;
  var synced = 0;
  for (final entry in await outbox.all()) {
    switch (entry.syncStatus) {
      case OutboxStatus.pending:
        pending++;
      case OutboxStatus.inProgress:
        inProgress++;
      case OutboxStatus.retryableFailure:
        retryable++;
      case OutboxStatus.conflict:
        conflict++;
      case OutboxStatus.requiresUserAction:
        userAction++;
      case OutboxStatus.permanentlyRejected:
        rejected++;
      case OutboxStatus.synced:
        synced++;
    }
  }
  return LocalWorkSnapshot(
    pending: pending,
    inProgress: inProgress,
    retryableFailure: retryable,
    conflict: conflict,
    requiresUserAction: userAction,
    permanentlyRejected: rejected,
    synced: synced,
    online: online,
  );
}

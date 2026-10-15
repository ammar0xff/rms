import '../local/outbox/outbox_entry.dart';
import '../local/outbox/outbox_status.dart';
import '../local/outbox/outbox_store.dart';
import 'retry_policy.dart';

/// Pushes a single outbox entry to the backend.
///
/// Implementations must be idempotent server-side: a repeated
/// [OutboxEntry.idempotencyKey] must be accepted at most once.
///
/// The returned map is any server acknowledgement to fold back into the entry
/// before it is marked synced, e.g. server-assigned ids such as `serverId` and
/// `canonicalOrderNumber`. Return an empty map when there is nothing to add.
abstract class SyncTransport {
  Future<Map<String, dynamic>> push(OutboxEntry entry);
}

typedef OutboxAppliedHandler = Future<void> Function(OutboxEntry entry);

/// Drains the transactional outbox.
///
/// Success marks the entry [OutboxStatus.synced]; failures record an incremented
/// attempt counter so [RetryPolicy] can back off. Because the transport dedupes
/// on the idempotency key, replaying a partially-applied batch never produces
/// duplicates.
class SyncEngine {
  SyncEngine({
    required SyncTransport transport,
    required OutboxStore outbox,
    RetryPolicy? retryPolicy,
    OutboxAppliedHandler? onApplied,
  })  : _transport = transport,
        _outbox = outbox,
        _retryPolicy = retryPolicy ?? RetryPolicy(),
        _onApplied = onApplied;

  final SyncTransport _transport;
  final OutboxStore _outbox;
  final RetryPolicy _retryPolicy;
  final OutboxAppliedHandler? _onApplied;

  /// Attempts every eligible pending entry once; returns how many were applied.
  Future<int> drain() async {
    final entries = await _outbox.pending();
    var applied = 0;
    final now = DateTime.now();
    for (final entry in entries) {
      if (entry.syncStatus == OutboxStatus.synced) continue;
      if (!_retryPolicy.shouldRetry(entry.attemptCount)) {
        // Budget exhausted: park the entry where a human can see it instead
        // of skipping it silently forever. A poison entry (e.g. a permanent
        // permission-denied the engine cannot distinguish from transient
        // failure) would otherwise sit in the retry queue eternally while the
        // update gate stays shut on its account.
        await _outbox.markNeedsUserAction(
          entry.operationId,
          'retry budget exhausted after ${entry.attemptCount} attempts'
          '${entry.lastError == null ? '' : ': ${entry.lastError}'}',
        );
        continue;
      }
      final lastAttempt = entry.lastAttemptAt;
      if (lastAttempt != null &&
          now.difference(lastAttempt) <
              _retryPolicy.nextDelay(entry.attemptCount)) {
        // Backoff has not elapsed. Without this every drain pass retried every
        // failure immediately, storming a flapping link and burning the whole
        // attempt budget in seconds instead of across the exponential schedule.
        continue;
      }
      await _outbox.markInProgress(entry.operationId);
      Map<String, dynamic> ack;
      try {
        ack = await _transport.push(entry);
        await _outbox.markSynced(entry.operationId, ack: ack);
      } catch (error) {
        await _outbox.markRetryable(entry.operationId, error.toString());
        continue;
      }
      if (_onApplied != null) {
        try {
          final synced = ack.isEmpty
              ? entry
              : entry.copyWith(payload: {...entry.payload, ...ack});
          await _onApplied(synced);
        } catch (error) {
          // The backend already holds this entry. Flipping it back to
          // retryable would re-push it — minting a second canonical order
          // number and duplicating audit rows — for what was a purely local
          // failure. Park it for a human instead.
          await _outbox.markNeedsUserAction(
            entry.operationId,
            'synced remotely but the local fold-back failed: $error',
          );
          continue;
        }
      }
      applied++;
    }
    return applied;
  }
}

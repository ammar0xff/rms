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
    for (final entry in entries) {
      if (entry.syncStatus == OutboxStatus.synced) continue;
      if (!_retryPolicy.shouldRetry(entry.attemptCount)) continue;
      await _outbox.markInProgress(entry.operationId);
      try {
        final ack = await _transport.push(entry);
        await _outbox.markSynced(entry.operationId, ack: ack);
        if (_onApplied != null) {
          final synced = ack.isEmpty
              ? entry
              : entry.copyWith(payload: {...entry.payload, ...ack});
          await _onApplied(synced);
        }
        applied++;
      } catch (error) {
        await _outbox.markRetryable(entry.operationId, error.toString());
      }
    }
    return applied;
  }
}

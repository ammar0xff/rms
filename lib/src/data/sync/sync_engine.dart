import '../local/outbox/outbox_entry.dart';
import '../local/outbox/outbox_status.dart';
import 'retry_policy.dart';

abstract class SyncTransport {
  Future<void> push(OutboxEntry entry);
}

class SyncEngine {
  SyncEngine({required SyncTransport transport, RetryPolicy? retryPolicy})
      : _transport = transport,
        _retryPolicy = retryPolicy ?? RetryPolicy();

  final SyncTransport _transport;
  final RetryPolicy _retryPolicy;

  Future<void> process(List<OutboxEntry> operations) async {
    for (final entry in operations) {
      if (entry.syncStatus == OutboxStatus.synced) continue;
      if (!_retryPolicy.shouldRetry(entry.attemptCount)) continue;
      try {
        await _transport.push(entry);
      } catch (_) {
        // left retryable; retry policy controls backoff on next pass
      }
    }
  }
}

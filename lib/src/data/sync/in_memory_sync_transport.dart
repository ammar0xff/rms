import '../local/outbox/outbox_entry.dart';
import 'sync_engine.dart';

/// A backend double for demo mode and tests.
///
/// Dedupes by [OutboxEntry.idempotencyKey] to emulate the server's exactly-once
/// guarantee, and can be toggled offline or made to fail the next push so retry
/// paths can be exercised.
class InMemorySyncTransport implements SyncTransport {
  final Set<String> _appliedKeys = {};
  final List<OutboxEntry> _accepted = [];

  bool online = true;
  bool failNextPush = false;

  int get appliedCount => _accepted.length;
  List<OutboxEntry> get accepted => List.unmodifiable(_accepted);

  bool hasApplied(String idempotencyKey) => _appliedKeys.contains(idempotencyKey);

  @override
  Future<void> push(OutboxEntry entry) async {
    if (!online) {
      throw StateError('Transport is offline');
    }
    if (failNextPush) {
      failNextPush = false;
      throw StateError('Simulated transient backend failure');
    }
    if (_appliedKeys.add(entry.idempotencyKey)) {
      _accepted.add(entry);
    }
  }
}

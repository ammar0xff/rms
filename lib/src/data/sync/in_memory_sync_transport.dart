import '../local/outbox/outbox_entry.dart';
import 'sync_engine.dart';

/// A backend double for demo mode and tests.
///
/// Dedupes by [OutboxEntry.idempotencyKey] to emulate the server's exactly-once
/// guarantee, and can be toggled offline or made to fail the next push so retry
/// paths can be exercised.
///
/// Like the real backend, it answers each push with an acknowledgement. Order
/// creations receive a server id and a canonical order number, so demo mode
/// exercises the same server-assigned identity path as production.
class InMemorySyncTransport implements SyncTransport {
  final Set<String> _appliedKeys = {};
  final List<OutboxEntry> _accepted = [];
  final Map<String, Map<String, dynamic>> _receipts = {};
  int _orderSeq = 0;

  bool online = true;
  bool failNextPush = false;

  int get appliedCount => _accepted.length;
  List<OutboxEntry> get accepted => List.unmodifiable(_accepted);

  bool hasApplied(String idempotencyKey) => _appliedKeys.contains(idempotencyKey);

  @override
  Future<Map<String, dynamic>> push(OutboxEntry entry) async {
    if (!online) {
      throw StateError('Transport is offline');
    }
    if (failNextPush) {
      failNextPush = false;
      throw StateError('Simulated transient backend failure');
    }
    final existing = _receipts[entry.idempotencyKey];
    if (existing != null) return existing;
    if (_appliedKeys.add(entry.idempotencyKey)) {
      _accepted.add(entry);
    }
    final ack = _ackFor(entry);
    _receipts[entry.idempotencyKey] = ack;
    return ack;
  }

  Map<String, dynamic> _ackFor(OutboxEntry entry) {
    final ack = <String, dynamic>{
      'serverId': 'srv-${entry.idempotencyKey}',
      'serverReceivedAt': DateTime.now().toIso8601String(),
    };
    if (entry.entityType == 'order' && entry.operationType == 'createOrder') {
      _orderSeq++;
      ack['canonicalOrderNumber'] = 'ORD-${_orderSeq.toString().padLeft(5, '0')}';
    }
    return ack;
  }
}

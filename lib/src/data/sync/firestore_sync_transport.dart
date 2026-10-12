import 'package:cloud_firestore/cloud_firestore.dart';

import '../local/outbox/outbox_entry.dart';
import 'sync_engine.dart';

/// Pushes outbox entries to Cloud Firestore.
///
/// The document id is the entry's [OutboxEntry.idempotencyKey], so replaying a
/// batch after a partial failure overwrites the same document instead of
/// creating duplicates — the server-side half of the exactly-once guarantee.
///
/// Order creations are additionally acknowledged with server-assigned identity:
/// the Firestore document id (`serverId`) and a monotonic canonical order number
/// (`canonicalOrderNumber`) drawn from a `counters/orders` document. Counter
/// assignment is best-effort: if the transaction fails the order still syncs
/// with its server id, and the canonical number is filled in on a later pass.
class FirestoreSyncTransport implements SyncTransport {
  FirestoreSyncTransport({
    FirebaseFirestore? firestore,
    this.collection = 'sync_operations',
    this.countersCollection = 'counters',
  }) : _firestore = firestore;

  final FirebaseFirestore? _firestore;
  final String collection;
  final String countersCollection;

  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;

  @override
  Future<Map<String, dynamic>> push(OutboxEntry entry) async {
    final ref = _db.collection(collection).doc(entry.idempotencyKey);
    await ref.set({
      'operationId': entry.operationId,
      'entityType': entry.entityType,
      'entityId': entry.entityId,
      'operationType': entry.operationType,
      'payload': entry.payload,
      'schemaVersion': entry.schemaVersion,
      'createdAt': entry.createdAt.toIso8601String(),
      'clientPushedAt': FieldValue.serverTimestamp(),
    });

    final ack = <String, dynamic>{
      'serverId': ref.id,
      'serverReceivedAt': DateTime.now().toIso8601String(),
    };
    if (entry.entityType == 'order' && entry.operationType == 'createOrder') {
      final canonical = await _assignCanonicalOrderNumber();
      if (canonical != null) ack['canonicalOrderNumber'] = canonical;
    }
    return ack;
  }

  /// Atomically reserves the next order number from `counters/orders`.
  /// Returns null when the reservation cannot be made, so a missing counter
  /// document or a restrictive security rule never blocks order sync.
  Future<String?> _assignCanonicalOrderNumber() async {
    try {
      final counter = _db.collection(countersCollection).doc('orders');
      final next = await _db.runTransaction<int>((txn) async {
        final snapshot = await txn.get(counter);
        final current = (snapshot.data()?['value'] as num?)?.toInt() ?? 0;
        final value = current + 1;
        txn.set(counter, {'value': value}, SetOptions(merge: true));
        return value;
      });
      return 'ORD-${next.toString().padLeft(5, '0')}';
    } catch (_) {
      return null;
    }
  }
}

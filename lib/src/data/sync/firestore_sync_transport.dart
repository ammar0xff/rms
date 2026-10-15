import 'package:cloud_firestore/cloud_firestore.dart';

import '../local/outbox/outbox_entry.dart';
import 'sync_ack.dart';
import 'sync_engine.dart';

/// Pushes outbox entries to Cloud Firestore.
///
/// The document id is the entry's [OutboxEntry.idempotencyKey], so replaying a
/// batch after a partial failure overwrites the same document instead of
/// creating duplicates — the server-side half of the exactly-once guarantee.
///
/// Order creations are additionally acknowledged with server-assigned identity:
/// the Firestore document id (`serverId`) and a monotonic canonical order number
/// (`canonicalOrderNumber`) drawn from a `counters/orders` document. A failed
/// reservation fails the push rather than syncing a numberless order: the entry
/// stays retryable and the number is reserved on a later pass. Syncing without
/// one would leave the order permanently unnumbered, since synced entries are
/// never re-pushed.
///
/// The shape of that acknowledgement is [SyncAck]'s, shared with the in-memory
/// transport, so demo mode cannot rehearse a contract production does not honour.
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
    final ref = _db.collection(collection).doc(SyncAck.documentId(entry));
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

    // Only order creations draw on the counter. A failed reservation throws
    // rather than returning a numberless ack: the entry stays retryable and a
    // synced-without-a-number order — unfixable, since synced entries are never
    // re-pushed — cannot happen.
    int? canonicalSequence;
    if (SyncAck.assignsCanonicalOrderNumber(entry)) {
      canonicalSequence = await _reuseOrReserveSequence(ref);
    }
    return SyncAck.build(
      entry: entry,
      serverId: ref.id,
      receivedAt: DateTime.now(),
      canonicalSequence: canonicalSequence,
    );
  }

  /// Returns the order number for this entry, reusing a previous reservation
  /// when this push is a replay.
  ///
  /// The reservation is written back into the operation document, so a replay —
  /// crash recovery, or a second attempt after the ack was lost — reads the
  /// number it already owns instead of burning a fresh one from the counter.
  /// Reserving unconditionally meant every replay consumed a new number while
  /// only the last ack was ever folded locally.
  Future<int> _reuseOrReserveSequence(
    DocumentReference<Map<String, dynamic>> ref,
  ) async {
    try {
      final existing = await ref.get();
      final owned = existing.data()?['canonicalOrderNumber'];
      if (owned is String) {
        final sequence = int.tryParse(owned.replaceFirst('ORD-', ''));
        if (sequence != null && sequence > 0) return sequence;
      }
    } catch (_) {
      // A failed read must not stop the reservation; worst case a number is
      // burned, which is a gap in the sequence, not a wrong order.
    }
    final sequence = await _reserveCanonicalSequence();
    await ref.set(
      {'canonicalOrderNumber': SyncAck.canonicalOrderNumber(sequence)},
      SetOptions(merge: true),
    );
    return sequence;
  }

  /// Atomically reserves the next order number from `counters/orders`.
  ///
  /// Throws when the reservation cannot be made, so the push fails and the
  /// entry stays retryable. A missing counter document or a restrictive
  /// security rule surfaces loudly instead of degrading into orders that sync
  /// without their canonical number and can never get one.
  Future<int> _reserveCanonicalSequence() async {
    final counter = _db.collection(countersCollection).doc('orders');
    return _db.runTransaction<int>((txn) async {
      final snapshot = await txn.get(counter);
      final current = (snapshot.data()?['value'] as num?)?.toInt() ?? 0;
      final value = current + 1;
      txn.set(counter, {'value': value}, SetOptions(merge: true));
      return value;
    });
  }
}

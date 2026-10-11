import 'package:cloud_firestore/cloud_firestore.dart';

import '../local/outbox/outbox_entry.dart';
import 'sync_engine.dart';

/// Pushes outbox entries to Cloud Firestore.
///
/// The document id is the entry's [OutboxEntry.idempotencyKey], so replaying a
/// batch after a partial failure overwrites the same document instead of
/// creating duplicates — the server-side half of the exactly-once guarantee.
class FirestoreSyncTransport implements SyncTransport {
  FirestoreSyncTransport({
    FirebaseFirestore? firestore,
    this.collection = 'sync_operations',
  }) : _firestore = firestore;

  final FirebaseFirestore? _firestore;
  final String collection;

  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;

  @override
  Future<void> push(OutboxEntry entry) async {
    await _db.collection(collection).doc(entry.idempotencyKey).set({
      'operationId': entry.operationId,
      'entityType': entry.entityType,
      'entityId': entry.entityId,
      'operationType': entry.operationType,
      'payload': entry.payload,
      'schemaVersion': entry.schemaVersion,
      'createdAt': entry.createdAt.toIso8601String(),
      'clientPushedAt': FieldValue.serverTimestamp(),
    });
  }
}

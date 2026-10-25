import 'package:cloud_firestore/cloud_firestore.dart';

/// Writes a local record snapshot to its mirror collection.
///
/// The outbox syncs *commands*; this mirrors *data*. On every acknowledgement
/// fold-back, the owning repository hands over its current record and the
/// mirror upserts it (merge by stable local id), so Firestore holds readable
/// `orders/`, `payments/`, … collections instead of only an opaque op log.
///
/// Best-effort by contract: implementations never throw. A mirror failure
/// must not break the sync it rides on — the outbox remains the channel of
/// record, the mirror a convenience that converges whenever the link allows.
abstract class RecordMirror {
  Future<void> write({
    required String entityType,
    required String entityId,
    required Map<String, Object?> snapshot,
  });
}

/// Best-effort write that never throws, for any implementation.
///
/// Repositories call this rather than the mirror directly, so the guarantee
/// holds even for a misbehaving [RecordMirror]: a mirror failure must never
/// break the fold-back (and the sync) it rides on.
Future<void> mirrorRecord(
  RecordMirror? mirror, {
  required String entityType,
  required String entityId,
  required Map<String, Object?> snapshot,
}) async {
  if (mirror == null) return;
  try {
    await mirror.write(
      entityType: entityType,
      entityId: entityId,
      snapshot: snapshot,
    );
  } catch (_) {
    // Best-effort stays best-effort.
  }
}

/// Entity type to mirror collection. Unknown types return null and are
/// skipped — the mirror only covers entities with a readable shape.
String? mirrorCollectionFor(String entityType) => switch (entityType) {
      'order' => 'orders',
      'payment' => 'payments',
      'collection' => 'collections',
      'delivery' => 'deliveries',
      'purchase' => 'purchases',
      'supplier' => 'suppliers',
      'kitchenTicket' => 'kitchenTickets',
      'stockMovement' => 'stockMovements',
      'inventoryItem' => 'inventoryItems',
      'cashSession' => 'cashSessions',
      'approval' => 'approvals',
      'customer' => 'customers',
      'menuItem' => 'menu',
      'table' => 'tables',
      'driver' => 'drivers',
      'deliveryZone' => 'delivery_zones',
      _ => null,
    };

/// Firestore-backed mirror. The instance is resolved lazily at call time —
/// like the transport — so constructing this before `initializeApp` cannot
/// crash startup. Called only from acknowledgement fold-back, i.e. right
/// after a successful push, so the link is known good.
class FirestoreRecordMirror implements RecordMirror {
  FirestoreRecordMirror({FirebaseFirestore? firestore}) : _firestore = firestore;

  final FirebaseFirestore? _firestore;

  @override
  Future<void> write({
    required String entityType,
    required String entityId,
    required Map<String, Object?> snapshot,
  }) async {
    final collection = mirrorCollectionFor(entityType);
    if (collection == null) return;
    try {
      final db = _firestore ?? FirebaseFirestore.instance;
      await db
          .collection(collection)
          .doc(entityId)
          .set({...snapshot, 'mirroredAt': DateTime.now().toIso8601String()},
              SetOptions(merge: true));
    } catch (_) {
      // Best-effort: swallow. The op log already holds everything needed to
      // reconstruct this; the mirror catches up on the next acknowledgement.
    }
  }
}

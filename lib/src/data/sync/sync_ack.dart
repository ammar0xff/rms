import '../local/outbox/outbox_entry.dart';

/// The acknowledgement contract shared by every [SyncTransport].
///
/// Both the Firestore transport and the in-memory one build their answers here,
/// rather than each assembling its own map. The acknowledgement is not
/// cosmetic: [applyAck] folds it into local records, so a shape that works in
/// demo mode and fails against the real backend is invisible until an order
/// loses its server identity in production.
///
/// Keeping the rules in one place also means demo mode is a faithful rehearsal
/// of the wire format instead of an approximation of it.
abstract final class SyncAck {
  /// Entity type whose creations receive a canonical order number.
  static const String entityOrder = 'order';

  /// Operation type that reserves a canonical order number.
  static const String operationCreateOrder = 'createOrder';

  /// The document an entry is written to.
  ///
  /// This is the whole of the exactly-once guarantee: a replay after a partial
  /// failure lands on the same document and overwrites it, rather than creating
  /// a second copy. It must stay keyed on the idempotency key and nothing else
  /// — keying on the entity id would collapse distinct operations, and keying
  /// on the operation id would defeat retry suppression entirely.
  static String documentId(OutboxEntry entry) => entry.idempotencyKey;

  /// Whether this entry should be given a canonical order number.
  ///
  /// Narrow on purpose: only order *creations* consume one. An update or a
  /// cancellation of an existing order must not draw a new number from the
  /// counter, or renumbering one order would burn the sequence for all of them.
  static bool assignsCanonicalOrderNumber(OutboxEntry entry) =>
      entry.entityType == entityOrder &&
      entry.operationType == operationCreateOrder;

  /// Renders a canonical order number, e.g. sequence 1 becomes `ORD-00001`.
  ///
  /// Zero-padded so the numbers sort lexicographically as they do numerically,
  /// which is what lets a report order by the string.
  static String canonicalOrderNumber(int sequence) =>
      'ORD-${sequence.toString().padLeft(5, '0')}';

  /// Builds the acknowledgement for a pushed entry.
  ///
  /// [canonicalSequence] is the reserved number, or null when none was reserved.
  /// Counter reservation is best-effort, so the order still syncs with its
  /// server id and the canonical number is filled in on a later pass; null
  /// leaves the field absent rather than writing a placeholder that would be
  /// indistinguishable from a real one.
  static Map<String, dynamic> build({
    required OutboxEntry entry,
    required String serverId,
    int? canonicalSequence,
  }) {
    final ack = <String, dynamic>{
      'serverId': serverId,
    };
    // Reserved numbers are 1-based: the counter document starts absent and the
    // first reservation is 1. A zero here means the counter moved backwards,
    // which is worth ignoring rather than stamping onto an order.
    if (canonicalSequence != null &&
        canonicalSequence > 0 &&
        assignsCanonicalOrderNumber(entry)) {
      ack['canonicalOrderNumber'] = canonicalOrderNumber(canonicalSequence);
    }
    return ack;
  }
}

/// Reads the contract's keys out of an acknowledgement.
///
/// The counterpart to [SyncAck.build]: the transport writes these keys and the
/// order repository reads them. Stated once here so both ends of the contract
/// are visible together, and a rename has to break something obvious.
///
/// Values of an unexpected type are ignored rather than cast, so a backend that
/// answers with something unexpected leaves the local record untouched instead
/// of throwing during sync.
abstract final class SyncAckReader {
  static String? serverId(Map<String, dynamic> ack) {
    final value = ack['serverId'];
    return value is String && value.isNotEmpty ? value : null;
  }

  static String? canonicalOrderNumber(Map<String, dynamic> ack) {
    final value = ack['canonicalOrderNumber'];
    return value is String && value.isNotEmpty ? value : null;
  }
}

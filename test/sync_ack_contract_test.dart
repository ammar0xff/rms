import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/data/local/outbox/outbox_entry.dart';
import 'package:rms/src/data/sync/in_memory_sync_transport.dart';
import 'package:rms/src/data/sync/sync_ack.dart';

OutboxEntry _entry({
  String entityType = 'order',
  String operationType = 'createOrder',
  String key = 'idem-1',
  String entityId = 'O-1',
  String operationId = 'op-1',
}) =>
    OutboxEntry(
      operationId: operationId,
      entityType: entityType,
      entityId: entityId,
      operationType: operationType,
      payload: const {'total': 10},
      schemaVersion: 1,
      idempotencyKey: key,
      createdAt: DateTime.utc(2026, 1, 1),
    );

Map<String, dynamic> _ack({
  OutboxEntry? entry,
  int? sequence,
}) =>
    SyncAck.build(
      entry: entry ?? _entry(),
      serverId: 'doc-1',
      canonicalSequence: sequence,
    );

void main() {
  group('exactly-once addressing', () {
    // Replaying a batch after a partial failure must land on the same document.
    // Keying on the entity id would collapse two distinct operations on one
    // entity into one, and keying on the operation id would defeat retry
    // suppression entirely, so this is the one invariant worth pinning tightly.
    test('the document is keyed on the idempotency key', () {
      expect(SyncAck.documentId(_entry(key: 'idem-1')), 'idem-1');
    });

    test('the document is keyed on neither the entity nor the operation', () {
      final entry = _entry(
        key: 'idem-9',
        entityId: 'O-9',
        operationId: 'op-9',
      );
      expect(SyncAck.documentId(entry), isNot('O-9'));
      expect(SyncAck.documentId(entry), isNot('op-9'));
    });
  });

  group('which entries draw on the order counter', () {
    test('an order creation does', () {
      expect(SyncAck.assignsCanonicalOrderNumber(_entry()), isTrue);
    });

    // Renumbering one order must not burn the sequence for every other order,
    // so updates and cancellations are excluded.
    test('an order update does not', () {
      expect(
        SyncAck.assignsCanonicalOrderNumber(_entry(operationType: 'updateOrder')),
        isFalse,
      );
    });

    test('an order cancellation does not', () {
      expect(
        SyncAck.assignsCanonicalOrderNumber(
          _entry(operationType: 'cancelOrder'),
        ),
        isFalse,
      );
    });

    test('a creation of something other than an order does not', () {
      expect(
        SyncAck.assignsCanonicalOrderNumber(
          _entry(entityType: 'payment'),
        ),
        isFalse,
      );
    });
  });

  group('canonical order numbers', () {
    test('are zero padded so lexical order matches numeric order', () {
      expect(SyncAck.canonicalOrderNumber(1), 'ORD-00001');
      expect(SyncAck.canonicalOrderNumber(42), 'ORD-00042');

      final sorted = [10, 9, 100, 1].map(SyncAck.canonicalOrderNumber).toList()
        ..sort();
      expect(sorted, ['ORD-00001', 'ORD-00009', 'ORD-00010', 'ORD-00100']);
    });

    test('do not truncate past the padding width', () {
      expect(SyncAck.canonicalOrderNumber(100000), 'ORD-100000');
    });
  });

  group('acknowledgement shape', () {
    test('carries the server id and nothing else by default', () {
      final ack = _ack();
      expect(ack['serverId'], 'doc-1');
      // serverReceivedAt used to ride along, written and folded but never read
      // by anything. A field with no reader is dead weight in every payload.
      expect(ack.containsKey('serverReceivedAt'), isFalse);
    });

    test('carries the canonical number when one was reserved', () {
      expect(_ack(sequence: 7)['canonicalOrderNumber'], 'ORD-00007');
    });

    // Counter reservation is best-effort: a restrictive security rule or a
    // missing counter document must not stop the order syncing.
    test('omits the canonical number when the reservation failed', () {
      final ack = _ack();
      expect(ack.containsKey('canonicalOrderNumber'), isFalse);
      expect(ack['serverId'], 'doc-1');
    });

    test('does not stamp a zero sequence onto an order', () {
      expect(
        _ack(sequence: 0).containsKey('canonicalOrderNumber'),
        isFalse,
      );
    });

    test('ignores a sequence supplied for an entry that wants none', () {
      expect(
        _ack(entry: _entry(entityType: 'payment'), sequence: 3)
            .containsKey('canonicalOrderNumber'),
        isFalse,
      );
    });
  });

  group('reading the acknowledgement back', () {
    test('returns what a transport wrote', () {
      final ack = _ack(sequence: 7);
      expect(SyncAckReader.serverId(ack), 'doc-1');
      expect(SyncAckReader.canonicalOrderNumber(ack), 'ORD-00007');
    });

    // An unexpected answer from the backend must leave the local record alone
    // rather than throw part-way through a sync.
    test('ignores a missing field', () {
      expect(SyncAckReader.serverId(<String, dynamic>{}), isNull);
      expect(SyncAckReader.canonicalOrderNumber(<String, dynamic>{}), isNull);
    });

    test('ignores a value of the wrong type', () {
      expect(SyncAckReader.serverId({'serverId': 9}), isNull);
      expect(
        SyncAckReader.canonicalOrderNumber({'canonicalOrderNumber': 7}),
        isNull,
      );
    });

    test('ignores an empty string', () {
      expect(SyncAckReader.serverId({'serverId': ''}), isNull);
    });
  });

  // The drift guard. Demo mode exists so it can rehearse production's wire
  // format; if the in-memory transport assembled its own acknowledgement, a
  // contract change would pass every test here and still fail against the real
  // backend.
  group('the in-memory transport honours the same contract', () {
    test('an order creation is acknowledged with a readable canonical number',
        () async {
      final transport = InMemorySyncTransport();
      final ack = await transport.push(_entry());

      expect(SyncAckReader.serverId(ack), isNotNull);
      expect(
        SyncAckReader.canonicalOrderNumber(ack),
        matches(RegExp(r'^ORD-\d{5}$')),
      );
    });

    test('a non-order entry is acknowledged without a canonical number',
        () async {
      final transport = InMemorySyncTransport();
      final ack = await transport.push(
        _entry(entityType: 'payment', key: 'idem-p'),
      );

      expect(SyncAckReader.serverId(ack), isNotNull);
      expect(SyncAckReader.canonicalOrderNumber(ack), isNull);
    });

    test('repeated pushes of one key do not consume the counter twice',
        () async {
      final transport = InMemorySyncTransport();
      final entry = _entry(key: 'idem-dup');

      final first = await transport.push(entry);
      final second = await transport.push(entry);

      // The replay returns the stored receipt rather than a fresh number, which
      // is the client half of the exactly-once guarantee.
      expect(second, first);
      expect(transport.appliedCount, 1);
    });

    test('distinct keys do consume the counter in turn', () async {
      final transport = InMemorySyncTransport();

      final first = await transport.push(_entry(key: 'a'));
      final second = await transport.push(_entry(key: 'b'));

      expect(
        SyncAckReader.canonicalOrderNumber(first),
        'ORD-00001',
      );
      expect(
        SyncAckReader.canonicalOrderNumber(second),
        'ORD-00002',
      );
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/data/local/local_database.dart';
import 'package:rms/src/data/local/outbox/outbox_entry.dart';
import 'package:rms/src/data/local/outbox/outbox_status.dart';
import 'package:rms/src/data/local/outbox/outbox_store.dart';
import 'package:rms/src/data/sync/in_memory_sync_transport.dart';
import 'package:rms/src/data/sync/sync_engine.dart';

int _seq = 0;

Future<LocalDatabase> _memoryDb() => LocalDatabase.memory('rms_ack_${_seq++}');

OutboxEntry _orderEntry({String key = 'k1'}) => OutboxEntry(
      operationId: 'op-$key',
      entityType: 'order',
      entityId: 'e-$key',
      operationType: 'createOrder',
      payload: const {'total': 10},
      schemaVersion: 1,
      idempotencyKey: key,
      createdAt: DateTime.utc(2026, 1, 1),
    );

void main() {
  test('a server acknowledgement is folded into the stored and applied entry',
      () async {
    final db = await _memoryDb();
    final store = OutboxStore(db);
    await db.transaction((txn) => store.append(txn, _orderEntry()));

    OutboxEntry? applied;
    final engine = SyncEngine(
      transport: InMemorySyncTransport(),
      outbox: store,
      onApplied: (entry) async => applied = entry,
    );

    expect(await engine.drain(), 1);

    // The applied entry sees the server-assigned identity.
    expect(applied, isNotNull);
    expect(applied!.payload['serverId'], isNotNull);
    expect(applied!.payload['canonicalOrderNumber'], startsWith('ORD-'));

    // ...and it is persisted on the outbox receipt.
    final stored = (await store.all()).single;
    expect(stored.syncStatus, OutboxStatus.synced);
    expect(stored.payload['serverId'], isNotNull);
    expect(stored.payload['canonicalOrderNumber'], startsWith('ORD-'));

    await db.close();
  });

  test('non-order entries still receive a server id', () async {
    final db = await _memoryDb();
    final store = OutboxStore(db);
    await db.transaction((txn) => store.append(
          txn,
          OutboxEntry(
            operationId: 'op-pay',
            entityType: 'payment',
            entityId: 'pay-1',
            operationType: 'recordPayment',
            payload: const {'amount': 5},
            schemaVersion: 1,
            idempotencyKey: 'pay-1',
            createdAt: DateTime.utc(2026, 1, 1),
          ),
        ));

    final engine = SyncEngine(transport: InMemorySyncTransport(), outbox: store);
    expect(await engine.drain(), 1);

    final stored = (await store.all()).single;
    expect(stored.payload['serverId'], isNotNull);
    expect(stored.payload.containsKey('canonicalOrderNumber'), isFalse);
    await db.close();
  });

  test('replaying a receipt returns the original acknowledgement', () async {
    final transport = InMemorySyncTransport();
    final first = await transport.push(_orderEntry(key: 'same'));
    final replay = await transport.push(_orderEntry(key: 'same'));
    expect(replay['serverId'], first['serverId']);
    expect(replay['canonicalOrderNumber'], first['canonicalOrderNumber']);
    expect(transport.appliedCount, 1);
  });
}

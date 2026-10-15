import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/data/local/local_database.dart';
import 'package:rms/src/data/local/outbox/outbox_entry.dart';
import 'package:rms/src/data/local/outbox/outbox_status.dart';
import 'package:rms/src/data/local/outbox/outbox_store.dart';
import 'package:rms/src/data/repositories/local_order_repository.dart';
import 'package:rms/src/data/repositories/local_payment_repository.dart';
import 'package:rms/src/data/sync/record_mirror.dart';
import 'package:rms/src/domain/models/order.dart';
import 'package:rms/src/domain/models/order_draft.dart';
import 'package:rms/src/domain/models/payment.dart';

int _seq = 0;

Future<LocalDatabase> _memoryDb() => LocalDatabase.memory('rms_mirror_${_seq++}');

class _Mirror implements RecordMirror {
  final List<({String type, String id, Map<String, Object?> snapshot})> calls =
      [];
  bool explode = false;

  @override
  Future<void> write({
    required String entityType,
    required String entityId,
    required Map<String, Object?> snapshot,
  }) async {
    if (explode) throw StateError('mirror down');
    calls.add((type: entityType, id: entityId, snapshot: snapshot));
  }
}

OutboxEntry _ack({
  required String entityType,
  required String entityId,
  Map<String, dynamic> ack = const {},
}) =>
    OutboxEntry(
      operationId: 'op-ack',
      entityType: entityType,
      entityId: entityId,
      operationType: 'ack',
      payload: ack,
      schemaVersion: 1,
      idempotencyKey: 'idem-ack',
      createdAt: DateTime(2026, 10, 15),
      syncStatus: OutboxStatus.synced,
    );

void main() {
  group('mirrorCollectionFor', () {
    test('maps every synced entity type', () {
      expect(mirrorCollectionFor('order'), 'orders');
      expect(mirrorCollectionFor('payment'), 'payments');
      expect(mirrorCollectionFor('collection'), 'collections');
      expect(mirrorCollectionFor('delivery'), 'deliveries');
      expect(mirrorCollectionFor('purchase'), 'purchases');
      expect(mirrorCollectionFor('supplier'), 'suppliers');
      expect(mirrorCollectionFor('kitchenTicket'), 'kitchenTickets');
      expect(mirrorCollectionFor('stockMovement'), 'stockMovements');
      expect(mirrorCollectionFor('inventoryItem'), 'inventoryItems');
      expect(mirrorCollectionFor('cashSession'), 'cashSessions');
      expect(mirrorCollectionFor('approval'), 'approvals');
    });

    test('returns null for unmapped types', () {
      expect(mirrorCollectionFor('driver'), isNull);
      expect(mirrorCollectionFor(''), isNull);
    });
  });

  group('fold-back mirroring', () {
    test('an order ack mirrors the settled snapshot with server identity',
        () async {
      final db = await _memoryDb();
      addTearDown(db.close);
      final mirror = _Mirror();
      final repo = LocalOrderRepository(
        db,
        outbox: OutboxStore(db),
        mirror: mirror,
      );

      final order = await repo.createOrder(OrderDraft(items: const [
        OrderItem(productId: 'p-1', name: 'صنف', unitPrice: 10, quantity: 2),
      ]));
      await repo.applySynced(_ack(
        entityType: 'order',
        entityId: order.localId,
        ack: const {
          'serverId': 'srv-1',
          'canonicalOrderNumber': 'ORD-00007',
        },
      ));

      expect(mirror.calls, hasLength(1));
      final call = mirror.calls.single;
      expect(call.type, 'order');
      expect(call.id, order.localId);
      // The mirror carries what the ack folded in — this is the whole point:
      // server identity visible in Firestore, not just the op log. (total
      // is computed, not stored, so the snapshot carries items + tax.)
      expect(call.snapshot['serverId'], 'srv-1');
      expect(call.snapshot['canonicalOrderNumber'], 'ORD-00007');
      expect((call.snapshot['items'] as List), hasLength(1));
    });

    test('a payment ack mirrors the payment', () async {
      final db = await _memoryDb();
      addTearDown(db.close);
      final mirror = _Mirror();
      final repo = LocalPaymentRepository(
        db,
        outbox: OutboxStore(db),
        mirror: mirror,
      );

      final payment = await repo.recordPayment(const PaymentDraft(
        orderLocalId: 'o-1',
        orderRef: 'O-1',
        amount: 42.0,
        method: PaymentMethod.cash,
      ));
      await repo.applySynced(_ack(
        entityType: 'payment',
        entityId: payment.id,
      ));

      expect(mirror.calls, hasLength(1));
      expect(mirror.calls.single.type, 'payment');
      expect(mirror.calls.single.snapshot['amount'], 42.0);
    });

    test('a mirror failure never breaks the fold-back', () async {
      final db = await _memoryDb();
      addTearDown(db.close);
      final mirror = _Mirror()..explode = true;
      final repo = LocalPaymentRepository(
        db,
        outbox: OutboxStore(db),
        mirror: mirror,
      );

      final payment = await repo.recordPayment(const PaymentDraft(
        orderLocalId: 'o-1',
        orderRef: 'O-1',
        amount: 42.0,
        method: PaymentMethod.cash,
      ));
      // Engine order first: the quiet guard would otherwise (correctly)
      // refuse while the create entry is still outstanding.
      final store = OutboxStore(db);
      for (final e in await store.all()) {
        await store.markSynced(e.operationId);
      }
      // Must not throw: the mirror is best-effort, the sync is not.
      await repo.applySynced(_ack(
        entityType: 'payment',
        entityId: payment.id,
      ));

      expect(
        (await repo.listPayments()).single.syncStatus,
        SyncStatus.synced,
      );
    });
  });
}

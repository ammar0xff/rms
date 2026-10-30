import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/data/local/local_database.dart';
import 'package:rms/src/data/local/outbox/outbox_store.dart';
import 'package:rms/src/data/repositories/local_order_repository.dart';
import 'package:rms/src/domain/models/order.dart';
import 'package:rms/src/domain/models/order_draft.dart';

int _rerouteDbSeq = 0;

void main() {
  group('Cross-Branch Order Rerouting', () {
    late LocalDatabase db;
    late OutboxStore outbox;
    late LocalOrderRepository orderRepo;

    setUp(() async {
      db = await LocalDatabase.memory('reroute_test_${_rerouteDbSeq++}');
      outbox = OutboxStore(db);
      orderRepo = LocalOrderRepository(db, outbox: outbox);
    });

    tearDown(() async {
      await db.close();
    });

    test('rerouteOrder updates branchId, increments revision, and appends outbox command', () async {
      final draft = OrderDraft(
        branchId: 'branch-dokki',
        items: const [
          OrderItem(
            productId: 'pizza-1',
            name: 'Pizza',
            unitPrice: 100.0,
            quantity: 1,
          ),
        ],
      );

      final created = await orderRepo.createOrder(draft);
      expect(created.branchId, 'branch-dokki');
      expect(created.localRevision, 1);

      // Reroute order to branch-maadi
      final updated = await orderRepo.rerouteOrder(
        orderId: created.localId,
        targetBranchId: 'branch-maadi',
      );

      expect(updated, isNotNull);
      expect(updated!.branchId, 'branch-maadi');
      expect(updated.localRevision, 2);

      // Verify persisted in store
      final listed = await orderRepo.listOrders();
      final persisted = listed.firstWhere((o) => o.localId == created.localId);
      expect(persisted.branchId, 'branch-maadi');
      expect(persisted.localRevision, 2);

      // Verify outbox entry
      final entries = await outbox.all();
      final rerouteEntry = entries.firstWhere((e) => e.operationType == 'rerouteOrder');
      expect(rerouteEntry.entityId, created.localId);
      expect(rerouteEntry.payload['targetBranchId'], 'branch-maadi');
      expect(rerouteEntry.payload['localRevision'], 2);
    });

    test('rerouteOrder returns null for non-existent order without crashing', () async {
      final result = await orderRepo.rerouteOrder(
        orderId: 'non-existent-order',
        targetBranchId: 'branch-nasr-city',
      );
      expect(result, isNull);
    });
  });
}

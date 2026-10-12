import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/data/local/outbox/outbox_status.dart';
import 'package:rms/src/domain/models/order.dart';
import 'package:rms/src/domain/models/order_draft.dart';

Order _order() => Order(
      localId: 'local-1',
      provisionalOrderNumber: 'O-20261011-ABC123',
      items: const [
        OrderItem(productId: 'p1', name: 'برجر', unitPrice: 45, quantity: 2),
        OrderItem(productId: 'p2', name: 'عصير', unitPrice: 15, quantity: 1),
      ],
      createdOffline: true,
    );

void main() {
  group('OrderItem', () {
    test('round-trips through a record', () {
      const item = OrderItem(
          productId: 'p1', name: 'برجر', unitPrice: 45.5, quantity: 2, station: 'حار');
      final restored = OrderItem.fromRecord(item.toRecord());
      expect(restored.productId, 'p1');
      expect(restored.name, 'برجر');
      expect(restored.unitPrice, 45.5);
      expect(restored.quantity, 2);
      expect(restored.station, 'حار');
    });

    test('station defaults to empty and is omitted from the record', () {
      const item =
          OrderItem(productId: 'p1', name: 'برجر', unitPrice: 45.5, quantity: 2);
      expect(item.station, isEmpty);
      expect(item.toRecord().containsKey('station'), isFalse);
      expect(OrderItem.fromRecord(item.toRecord()).station, isEmpty);
    });
  });

  group('Order', () {
    test('computes the total from its line items', () {
      expect(_order().total, 105);
    });

    test('defaults to local-only status', () {
      expect(_order().syncStatus, SyncStatus.localOnly);
    });

    test('round-trips through a record', () {
      final order = _order()
        ..syncStatus = SyncStatus.pendingSync
        ..serverId = 'srv-9'
        ..canonicalOrderNumber = 'ORD-4821';

      final restored = Order.fromRecord(order.toRecord());
      expect(restored.localId, 'local-1');
      expect(restored.provisionalOrderNumber, 'O-20261011-ABC123');
      expect(restored.items, hasLength(2));
      expect(restored.items.first.name, 'برجر');
      expect(restored.items.first.unitPrice, 45);
      expect(restored.createdOffline, isTrue);
      expect(restored.serverId, 'srv-9');
      expect(restored.canonicalOrderNumber, 'ORD-4821');
      expect(restored.syncStatus, SyncStatus.pendingSync);
    });
  });

  group('OrderDraft', () {
    test('defaults to an online creation and exposes its items', () {
      const draft = OrderDraft(
        items: [OrderItem(productId: 'p', name: 'n', unitPrice: 1, quantity: 1)],
      );
      expect(draft.createdOffline, isFalse);
      expect(draft.items, hasLength(1));
    });
  });
}

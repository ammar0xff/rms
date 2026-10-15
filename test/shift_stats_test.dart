import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/data/local/outbox/outbox_status.dart';
import 'package:rms/src/domain/models/order.dart';
import 'package:rms/src/domain/models/order_type.dart';
import 'package:rms/src/features/shift/shift_screen.dart';

Order _order({
  required double total,
  required DateTime createdAt,
  SyncStatus synced = SyncStatus.synced,
}) {
  final items = [
    OrderItem(productId: 'p', name: 'صنف', unitPrice: total, quantity: 1),
  ];
  return Order(
    localId: 'l-${createdAt.millisecondsSinceEpoch}',
    provisionalOrderNumber: 'O-1',
    items: items,
    createdOffline: false,
    createdAt: createdAt,
    orderType: OrderType.dineIn,
    syncStatus: synced,
  );
}

void main() {
  final day = DateTime(2026, 10, 15, 12);
  final yesterday = DateTime(2026, 10, 14, 23, 59);

  group('ShiftStats.of', () {
    test('counts today only', () {
      final stats = ShiftStats.of(
        [
          _order(total: 100, createdAt: day),
          _order(total: 200, createdAt: day),
          _order(total: 9999, createdAt: yesterday),
        ],
        day,
      );

      expect(stats.orders, 2);
      expect(stats.sales, 300);
      expect(stats.recent, hasLength(2));
    });

    test('averages and handles the empty day', () {
      final stats = ShiftStats.of(
        [_order(total: 100, createdAt: day)],
        day,
      );
      expect(stats.averageTicket, 100);

      final empty = ShiftStats.of([], day);
      expect(empty.averageTicket, 0);
      expect(empty.sales, 0);
      expect(empty.orders, 0);
      expect(empty.recent, isEmpty);
    });

    test('unsynced sums only what is still owed', () {
      final stats = ShiftStats.of(
        [
          _order(total: 100, createdAt: day, synced: SyncStatus.synced),
          _order(total: 50, createdAt: day, synced: SyncStatus.pendingSync),
        ],
        day,
      );

      expect(stats.unsynced, 50);
    });

    test('recent is newest first and capped at five', () {
      final stats = ShiftStats.of(
        [
          for (var h = 8; h < 15; h++)
            _order(
                total: 10,
                createdAt: DateTime(2026, 10, 15, h)),
        ],
        DateTime(2026, 10, 15, 20),
      );

      expect(stats.recent, hasLength(5));
      expect(stats.recent.first.createdAt.hour, 14);
    });
  });
}

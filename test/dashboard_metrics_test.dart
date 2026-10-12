import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/data/local/outbox/outbox_status.dart';
import 'package:rms/src/domain/models/order.dart';
import 'package:rms/src/features/dashboard/dashboard_metrics.dart';

Order _order({
  required DateTime createdAt,
  double unitPrice = 10,
  int quantity = 1,
  bool createdOffline = false,
  SyncStatus syncStatus = SyncStatus.pendingSync,
}) =>
    Order(
      localId: 'local-${createdAt.microsecondsSinceEpoch}-$unitPrice',
      provisionalOrderNumber: 'O-x',
      items: [
        OrderItem(
          productId: 'p',
          name: 'صنف',
          unitPrice: unitPrice,
          quantity: quantity,
        ),
      ],
      createdOffline: createdOffline,
      createdAt: createdAt,
      syncStatus: syncStatus,
    );

void main() {
  final now = DateTime(2026, 10, 12, 13, 30);

  test('empty order list yields zeroed metrics', () {
    final m = DashboardMetrics.fromOrders(const [], now: now);
    expect(m.todayTotal, 0);
    expect(m.todayOrders, 0);
    expect(m.averageTicket, 0);
    expect(m.offlineOrders, 0);
    expect(m.unsyncedOrders, 0);
    expect(m.hourlySales, hasLength(DashboardMetrics.bucketCount));
    expect(m.hourlySales.every((v) => v == 0), isTrue);
    expect(m.peakIndex, 0);
  });

  test('aggregates today totals, count and average ticket', () {
    final m = DashboardMetrics.fromOrders([
      _order(createdAt: now, unitPrice: 20, quantity: 2),
      _order(createdAt: DateTime(2026, 10, 12, 9), unitPrice: 30),
    ], now: now);

    expect(m.todayOrders, 2);
    expect(m.todayTotal, 70);
    expect(m.averageTicket, 35);
  });

  test('ignores orders from other days', () {
    final m = DashboardMetrics.fromOrders([
      _order(createdAt: now),
      _order(createdAt: DateTime(2026, 10, 11, 23, 59)),
      _order(createdAt: DateTime(2026, 10, 13)),
    ], now: now);

    expect(m.todayOrders, 1);
  });

  test('counts offline and unsynced orders', () {
    final m = DashboardMetrics.fromOrders([
      _order(createdAt: now, createdOffline: true),
      _order(createdAt: now, syncStatus: SyncStatus.synced),
      _order(createdAt: now, syncStatus: SyncStatus.conflict),
    ], now: now);

    expect(m.offlineOrders, 1);
    expect(m.unsyncedOrders, 2);
  });

  test('buckets sales by hour and finds the peak', () {
    final m = DashboardMetrics.fromOrders([
      _order(createdAt: DateTime(2026, 10, 12, 11), unitPrice: 10),
      _order(createdAt: DateTime(2026, 10, 12, 15), unitPrice: 40),
      _order(createdAt: DateTime(2026, 10, 12, 15), unitPrice: 20),
      // Outside the 10:00–21:00 chart window but still part of today's total.
      _order(createdAt: DateTime(2026, 10, 12, 8), unitPrice: 100),
    ], now: now);

    expect(m.todayTotal, 170);
    expect(m.peakIndex, 5); // 15:00 → index 5
    expect(m.hourlySales[1], 10); // 11:00
    expect(m.hourlySales[5], 60); // 15:00
    expect(m.hourlySales.reduce((a, b) => a + b), 70); // excludes the 08:00 order
  });
}

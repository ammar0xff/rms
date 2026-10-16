import '../../data/local/outbox/outbox_status.dart';
import '../../domain/models/order.dart';

/// Presentation-agnostic KPIs derived from the local order store.
///
/// Extracted from the dashboard so the "today" filtering and hourly bucketing
/// can be unit-tested without a widget tree.
class DashboardMetrics {
  const DashboardMetrics({
    required this.todayTotal,
    required this.todayOrders,
    required this.averageTicket,
    required this.offlineOrders,
    required this.unsyncedOrders,
    required this.hourlySales,
    required this.peakIndex,
  });

  /// First hour covered by the sales-by-hour chart (10:00 local).
  static const int firstHour = 10;

  /// Number of hourly buckets shown on the chart.
  static const int bucketCount = 12;

  final double todayTotal;
  final int todayOrders;
  final double averageTicket;
  final int offlineOrders;
  final int unsyncedOrders;

  /// Sales total per hour, indexed from [firstHour].
  final List<double> hourlySales;

  /// Index into [hourlySales] with the highest total (0 when all are zero).
  final int peakIndex;

  static DashboardMetrics fromOrders(List<Order> orders, {DateTime? now}) {
    final at = now ?? DateTime.now();
    final hourly = List<double>.filled(bucketCount, 0);
    var total = 0.0;
    var count = 0;
    var offline = 0;
    var unsynced = 0;

    for (final order in orders) {
      if (!_isSameDay(order.createdAt, at)) continue;
      if (order.voided) continue;
      count++;
      total += order.total;
      if (order.createdOffline) offline++;
      if (order.syncStatus != SyncStatus.synced) unsynced++;
      final hour = order.createdAt.hour;
      if (hour >= firstHour && hour < firstHour + bucketCount) {
        hourly[hour - firstHour] += order.total;
      }
    }

    var peak = 0;
    for (var i = 1; i < hourly.length; i++) {
      if (hourly[i] > hourly[peak]) peak = i;
    }

    return DashboardMetrics(
      todayTotal: total,
      todayOrders: count,
      averageTicket: count == 0 ? 0 : total / count,
      offlineOrders: offline,
      unsyncedOrders: unsynced,
      hourlySales: hourly,
      peakIndex: peak,
    );
  }

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

import 'package:flutter/material.dart';
import '../../core/di/app_services.dart';
import '../../core/theme/pie_colors.dart';
import '../../core/theme/pie_typography.dart';
import '../../core/widgets/pie_card.dart';
import '../../core/widgets/pie_numeral.dart';
import '../../domain/models/approval_request.dart';
import '../../domain/models/cash_session.dart';
import '../../domain/models/delivery.dart';
import '../../domain/models/inventory_item.dart';
import '../../domain/models/order.dart';
import '../../domain/models/order_type.dart';

/// Screen 16: Command Dashboard (لوحة القيادة والمتابعة اللحظية للمدير)
///
/// Functional contract:
/// - Shift state & Net sales hero
/// - KPI grid from real database records
/// - Sales channel breakdown (hall / takeaway / delivery)
/// - Hourly volume with the peak marked
/// - Alerts that are real operational thresholds
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: PieColors.canvas,
        appBar: AppBar(
          title: Text('لوحة قيادة العمليات', style: PieTypography.heading),
        ),
        body: FutureBuilder(
          future: Future.wait([
            services.orders?.listOrders() ?? Future.value(<Order>[]),
            services.deliveries?.listDeliveries() ?? Future.value(<DeliveryModel>[]),
            services.approvals?.listRequests() ?? Future.value(<ApprovalRequest>[]),
            services.inventory?.listItems() ?? Future.value(<InventoryItemModel>[]),
            services.cashSessions?.currentSession() ?? Future.value(null),
          ]),
          builder: (context, AsyncSnapshot<List<dynamic>> snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final orders = (snapshot.data![0] as List).cast<Order>();
            final deliveries = (snapshot.data![1] as List).cast<DeliveryModel>();
            final approvals = (snapshot.data![2] as List).cast<ApprovalRequest>();
            final inventory = (snapshot.data![3] as List).cast<InventoryItemModel>();
            final session = snapshot.data![4] as CashSession?;

            final activeOrders = orders.where((o) => !o.voided).toList();
            final netSales = activeOrders.fold(0.0, (sum, o) => sum + o.total);
            final avgTicket = activeOrders.isEmpty ? 0.0 : netSales / activeOrders.length;

            // Channel Breakdown calculations
            final dineInTotal = activeOrders
                .where((o) => o.orderType == OrderType.dineIn)
                .fold(0.0, (sum, o) => sum + o.total);
            final takeawayTotal = activeOrders
                .where((o) => o.orderType == OrderType.takeaway)
                .fold(0.0, (sum, o) => sum + o.total);
            final deliveryTotal = activeOrders
                .where((o) => o.orderType == OrderType.delivery)
                .fold(0.0, (sum, o) => sum + o.total);

            // Real threshold alerts
            final unassignedDeliveries = deliveries
                .where((d) => d.state == DeliveryState.waiting)
                .toList();
            final pendingApprovals = approvals.where((a) => a.isPending).toList();
            final lowStockItems = inventory.where((i) => i.isLow).toList();

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Net Sales Hero Card
                _buildNetSalesHero(session, netSales, activeOrders.length),
                const SizedBox(height: 16),

                // Real threshold alerts (only rendered when thresholds breached!)
                if (unassignedDeliveries.isNotEmpty || pendingApprovals.isNotEmpty || lowStockItems.isNotEmpty) ...[
                  _buildAlertsSection(
                    unassignedCount: unassignedDeliveries.length,
                    approvalsCount: pendingApprovals.length,
                    lowStockCount: lowStockItems.length,
                  ),
                  const SizedBox(height: 16),
                ],

                // KPI Grid
                _buildKpiGrid(
                  ordersCount: activeOrders.length,
                  avgTicket: avgTicket,
                  deliveriesCount: deliveries.where((d) => d.state != DeliveryState.delivered).length,
                  lowStockCount: lowStockItems.length,
                ),
                const SizedBox(height: 20),

                // Sales Channel Breakdown Card
                _buildChannelBreakdownCard(
                  total: netSales,
                  dineIn: dineInTotal,
                  takeaway: takeawayTotal,
                  delivery: deliveryTotal,
                ),
                const SizedBox(height: 20),

                // Hourly Volume Distribution with Peak Marked
                _buildHourlyVolumeCard(activeOrders),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildNetSalesHero(CashSession? session, double netSales, int ordersCount) {
    final isOpen = session?.isOpen ?? true;

    return PieCard(
      padding: const EdgeInsets.all(22),
      surfaceColor: PieColors.surface2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('صافي مبيعات وردية اليوم', style: PieTypography.subheading),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isOpen ? const Color(0xFF052E16) : PieColors.stateErrorBg,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isOpen ? const Color(0xFF4ADE80) : PieColors.stateError,
                  ),
                ),
                child: Text(
                  isOpen ? 'الوردية نشطة' : 'الوردية مغلقة',
                  style: PieTypography.caption.copyWith(
                    color: isOpen ? const Color(0xFF4ADE80) : PieColors.stateError,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          PieNumeral.money(
            netSales,
            style: PieTypography.monoDisplay.copyWith(
              color: PieColors.managerAccent,
              fontSize: 34,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'محصلة $ordersCount أوردرات منفذة بدون الفواتير الملغاة.',
            style: PieTypography.caption.copyWith(color: PieColors.inkSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertsSection({
    required int unassignedCount,
    required int approvalsCount,
    required int lowStockCount,
  }) {
    return Column(
      children: [
        if (approvalsCount > 0) ...[
          _buildAlertBanner(
            icon: Icons.approval_rounded,
            title: '$approvalsCount موافقات إدارية معلقة',
            subtitle: 'طلبات إلغاء واسترجاع بانتظار إدخال الـ PIN',
            color: PieColors.managerAccent,
          ),
          const SizedBox(height: 8),
        ],
        if (unassignedCount > 0) ...[
          _buildAlertBanner(
            icon: Icons.two_wheeler_rounded,
            title: '$unassignedCount أوردرات دليفري بدون طيار',
            subtitle: 'الأوردرات جاهزة للتوزيع ولم تسند لكابتن بعد',
            color: PieColors.driverAccent,
          ),
          const SizedBox(height: 8),
        ],
        if (lowStockCount > 0) ...[
          _buildAlertBanner(
            icon: Icons.inventory_2_outlined,
            title: '$lowStockCount خامات تخطت نقطة إعادة الطلب',
            subtitle: 'المخزون أقل من الحد الأدنى للتشغيل الآمن',
            color: PieColors.stateError,
          ),
        ],
      ],
    );
  }

  Widget _buildAlertBanner({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: PieTypography.bodyStrong.copyWith(color: color)),
                Text(subtitle, style: PieTypography.caption.copyWith(color: PieColors.inkSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKpiGrid({
    required int ordersCount,
    required double avgTicket,
    required int deliveriesCount,
    required int lowStockCount,
  }) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.6,
      children: [
        _buildKpiCard('عدد الأوردرات', '$ordersCount أوردر', Icons.receipt_long_rounded),
        _buildKpiCard('متوسط الفاتورة', PieTypography.formatEgp(avgTicket), Icons.analytics_outlined),
        _buildKpiCard('دليفري قيد التنفيذ', '$deliveriesCount أوردر', Icons.delivery_dining_rounded),
        _buildKpiCard('نواقص المخزون', '$lowStockCount صنف', Icons.warning_amber_rounded),
      ],
    );
  }

  Widget _buildKpiCard(String label, String value, IconData icon) {
    return PieCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: PieTypography.caption),
              Icon(icon, size: 16, color: PieColors.inkMuted),
            ],
          ),
          Text(
            value,
            style: PieTypography.heading.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _buildChannelBreakdownCard({
    required double total,
    required double dineIn,
    required double takeaway,
    required double delivery,
  }) {
    final dineInPct = total > 0 ? (dineIn / total) : 0.33;
    final takeawayPct = total > 0 ? (takeaway / total) : 0.33;
    final deliveryPct = total > 0 ? (delivery / total) : 0.34;

    return PieCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'توزيع المبيعات حسب القنوات',
            style: PieTypography.subheading.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 14),
          // Proportion Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 12,
              child: Row(
                children: [
                  Expanded(
                    flex: (dineInPct * 100).toInt().clamp(1, 100),
                    child: Container(color: const Color(0xFF60A5FA)),
                  ),
                  Expanded(
                    flex: (takeawayPct * 100).toInt().clamp(1, 100),
                    child: Container(color: const Color(0xFFFBBF24)),
                  ),
                  Expanded(
                    flex: (deliveryPct * 100).toInt().clamp(1, 100),
                    child: Container(color: PieColors.driverAccent),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Breakdown numbers
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildChannelStat('صالة', dineIn, const Color(0xFF60A5FA)),
              _buildChannelStat('تيك أواي', takeaway, const Color(0xFFFBBF24)),
              _buildChannelStat('دليفري', delivery, PieColors.driverAccent),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChannelStat(String label, double amount, Color dotColor) {
    return Column(
      children: [
        Row(
          children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(label, style: PieTypography.caption),
          ],
        ),
        const SizedBox(height: 4),
        PieNumeral.money(amount, style: PieTypography.monoBody.copyWith(fontWeight: FontWeight.w700)),
      ],
    );
  }

  Widget _buildHourlyVolumeCard(List<Order> orders) {
    // Group orders into hourly slots
    final hourCounts = <int, int>{};
    for (var h = 10; h <= 23; h++) {
      hourCounts[h] = 0;
    }
    for (final o in orders) {
      final hour = o.createdAt.hour;
      hourCounts[hour] = (hourCounts[hour] ?? 0) + 1;
    }

    var peakHour = 14;
    var maxCount = 0;
    hourCounts.forEach((h, c) {
      if (c > maxCount) {
        maxCount = c;
        peakHour = h;
      }
    });

    return PieCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'حجم الطلبات بالساعة',
                style: PieTypography.subheading.copyWith(fontWeight: FontWeight.w700),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: PieColors.surface2,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'ذروة النشاط: $peakHour:00 ($maxCount أوردر)',
                  style: PieTypography.caption.copyWith(
                    color: PieColors.managerAccent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          // Hourly Histogram
          SizedBox(
            height: 90,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final entry in hourCounts.entries) ...[
                  _buildHourBar(
                    hour: entry.key,
                    count: entry.value,
                    isPeak: entry.key == peakHour && maxCount > 0,
                    maxCount: maxCount > 0 ? maxCount : 1,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHourBar({
    required int hour,
    required int count,
    required bool isPeak,
    required int maxCount,
  }) {
    final heightFactor = (count / maxCount).clamp(0.1, 1.0);

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Container(
              height: 60 * heightFactor,
              decoration: BoxDecoration(
                color: isPeak ? PieColors.managerAccent : PieColors.surface3,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '$hour',
              style: PieTypography.monoCaption.copyWith(fontSize: 9),
            ),
          ],
        ),
      ),
    );
  }
}

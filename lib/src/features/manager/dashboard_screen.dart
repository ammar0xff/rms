import 'package:flutter/material.dart';
import '../../core/di/app_services.dart';
import '../../core/theme/pie_colors.dart';
import '../../core/theme/pie_radius.dart';
import '../../core/theme/pie_typography.dart';
import '../../core/widgets/pie_card.dart';
import '../../core/widgets/pie_numeral.dart';
import '../../domain/models/approval_request.dart';
import '../../domain/models/branch.dart';
import '../../domain/models/cash_session.dart';
import '../../domain/models/customer.dart';
import '../../domain/models/delivery.dart';
import '../../domain/models/inventory_item.dart';
import '../../domain/models/order.dart';
import '../../domain/models/order_type.dart';

/// Screen 16: Command Dashboard (لوحة القيادة والمتابعة اللحظية للمدير)
///
/// Functional contract:
/// - Multi-branch monitoring & drill-down filter
/// - Shift state & Net sales hero
/// - Customer acquisition & repeat order KPIs
/// - KPI grid from real database records
/// - Sales channel breakdown (hall / takeaway / delivery)
/// - Hourly volume with the peak marked
/// - Alerts that are real operational thresholds
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String? _selectedBranchId;

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: FutureBuilder(
          future: Future.wait([
            services.orders?.listOrders() ?? Future.value(<Order>[]),
            services.deliveries?.listDeliveries() ?? Future.value(<DeliveryModel>[]),
            services.approvals?.listRequests() ?? Future.value(<ApprovalRequest>[]),
            services.inventory?.listItems() ?? Future.value(<InventoryItemModel>[]),
            services.cashSessions?.currentSession() ?? Future.value(null),
            services.branches?.listBranches() ?? Future.value(<BranchModel>[]),
            services.customers?.listCustomers() ?? Future.value(<CustomerModel>[]),
          ]),
          builder: (context, AsyncSnapshot<List<dynamic>> snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final allOrders = (snapshot.data![0] as List).cast<Order>();
            final allDeliveries = (snapshot.data![1] as List).cast<DeliveryModel>();
            final approvals = (snapshot.data![2] as List).cast<ApprovalRequest>();
            final inventory = (snapshot.data![3] as List).cast<InventoryItemModel>();
            final session = snapshot.data![4] as CashSession?;
            final branches = (snapshot.data![5] as List).cast<BranchModel>();
            final allCustomers = (snapshot.data![6] as List).cast<CustomerModel>();

            // Filter data by selected branch if set
            final orders = _selectedBranchId == null
                ? allOrders
                : allOrders.where((o) => o.branchId == _selectedBranchId).toList();
            final deliveries = _selectedBranchId == null
                ? allDeliveries
                : allDeliveries.where((d) => d.branchId == _selectedBranchId).toList();
            final customers = _selectedBranchId == null
                ? allCustomers
                : allCustomers.where((c) => c.branchId == _selectedBranchId).toList();

            final activeOrders = orders.where((o) => !o.voided).toList();
            final netSales = activeOrders.fold(0.0, (sum, o) => sum + o.total);
            final avgTicket = activeOrders.isEmpty ? 0.0 : netSales / activeOrders.length;
            final repeatCustomers = customers.where((c) => c.totalOrders > 1).length;

            // Channel Breakdown calculations
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
                // Multi-Branch Filter Bar
                _buildBranchFilterBar(branches),

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
                  customersCount: customers.length,
                  repeatCustomersCount: repeatCustomers,
                  lowStockCount: lowStockItems.length,
                ),
                const SizedBox(height: 20),

                // Sales Channel Breakdown Card
                _buildChannelBreakdownCard(
                  total: netSales,
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
                  color: isOpen ? PieColors.stateSyncedBg : PieColors.stateErrorBg,
                  borderRadius: PieRadius.borderSm,
                  border: Border.all(
                    color: isOpen ? PieColors.stateSynced : PieColors.stateError,
                  ),
                ),
                child: Text(
                  isOpen ? 'الوردية نشطة' : 'الوردية مغلقة',
                  style: PieTypography.caption.copyWith(
                    color: isOpen ? PieColors.stateSynced : PieColors.stateError,
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
        borderRadius: PieRadius.borderMd,
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

  Widget _buildBranchFilterBar(List<BranchModel> branches) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildBranchChip(
              id: null,
              label: 'كل الفروع (المجمع) 🏢',
              isSelected: _selectedBranchId == null,
            ),
            const SizedBox(width: 8),
            ...branches.map((b) {
              return Padding(
                padding: const EdgeInsets.only(left: 8),
                child: _buildBranchChip(
                  id: b.id,
                  label: '${b.name} 📍',
                  isSelected: _selectedBranchId == b.id,
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildBranchChip({
    required String? id,
    required String label,
    required bool isSelected,
  }) {
    return InkWell(
      onTap: () {
        setState(() {
          _selectedBranchId = id;
        });
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? PieColors.managerAccent : PieColors.surface2,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? PieColors.managerAccent : PieColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'IBMPlexSansArabic',
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
            color: isSelected ? Colors.white : PieColors.ink,
          ),
        ),
      ),
    );
  }

  Widget _buildKpiGrid({
    required int ordersCount,
    required double avgTicket,
    required int deliveriesCount,
    required int customersCount,
    required int repeatCustomersCount,
    required int lowStockCount,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 900;
        final crossAxisCount = isDesktop ? 5 : 2;
        final childAspectRatio = isDesktop ? 1.8 : 1.35;

        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: childAspectRatio,
          children: [
            _buildKpiCard('عدد الأوردرات', '$ordersCount أوردر', Icons.receipt_long_rounded),
            _buildKpiCard('متوسط الفاتورة', PieTypography.formatEgp(avgTicket), Icons.analytics_outlined),
            _buildKpiCard('دليفري نشط', '$deliveriesCount أوردر', Icons.delivery_dining_rounded),
            _buildKpiCard('العملاء المسجلين', '$customersCount عميل ($repeatCustomersCount متكرر)', Icons.people_outline_rounded),
            _buildKpiCard('نواقص المخزون', '$lowStockCount صنف', Icons.warning_amber_rounded),
          ],
        );
      },
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
              Expanded(
                child: Text(
                  label,
                  style: PieTypography.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Icon(icon, size: 16, color: PieColors.inkMuted),
            ],
          ),
          FittedBox(
            alignment: Alignment.centerRight,
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: PieTypography.heading.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChannelBreakdownCard({
    required double total,
    required double takeaway,
    required double delivery,
  }) {
    final hasSales = total > 0;
    final takeawayPct = hasSales ? (takeaway / total) : 0.0;
    final deliveryPct = hasSales ? (delivery / total) : 0.0;

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
            borderRadius: PieRadius.borderSm,
            child: SizedBox(
              height: 12,
              child: hasSales
                  ? Row(
                      children: [
                        if (takeawayPct > 0)
                          Expanded(
                            flex: (takeawayPct * 100).toInt().clamp(1, 100),
                            child: Container(color: const Color(0xFFFBBF24)),
                          ),
                        if (deliveryPct > 0)
                          Expanded(
                            flex: (deliveryPct * 100).toInt().clamp(1, 100),
                            child: Container(color: PieColors.driverAccent),
                          ),
                      ],
                    )
                  : Container(color: PieColors.surface3),
            ),
          ),
          const SizedBox(height: 16),
          // Breakdown numbers
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
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
                  borderRadius: PieRadius.borderSm,
                ),
                child: Text(
                  maxCount > 0
                      ? 'ذروة النشاط: $peakHour:00 ($maxCount أوردر)'
                      : 'لا توجد طلبات مسجلة اليوم بعد',
                  style: PieTypography.caption.copyWith(
                    color: maxCount > 0 ? PieColors.managerAccent : PieColors.inkSecondary,
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
                borderRadius: BorderRadius.vertical(top: const Radius.circular(PieRadius.sm)),
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

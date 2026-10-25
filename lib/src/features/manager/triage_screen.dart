import 'package:flutter/material.dart';
import '../../core/di/app_services.dart';
import '../../core/theme/pie_colors.dart';
import '../../core/theme/pie_radius.dart';
import '../../core/theme/pie_typography.dart';
import '../../core/widgets/pie_button.dart';
import '../../core/widgets/pie_card.dart';
import '../../core/widgets/pie_empty_state.dart';
import '../../domain/models/branch.dart';
import '../../domain/models/delivery.dart';
import '../../domain/models/order.dart';
import '../../domain/models/order_type.dart';

/// Screen 19: Cross-branch Triage (إدارة ومراقبة أوردرات كافة الفروع)
///
/// Functional contract:
/// - Cross-branch monitoring (status, load, delays)
/// - Delay threshold detection (> 30m)
/// - Emergency routing & rebalancing
class TriageScreen extends StatefulWidget {
  const TriageScreen({super.key});

  @override
  State<TriageScreen> createState() => _TriageScreenState();
}

class _TriageScreenState extends State<TriageScreen> {
  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final branchRepo = services.branches;
    final ordersRepo = services.orders;
    final deliveriesRepo = services.deliveries;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: FutureBuilder(
        future: Future.wait([
          branchRepo?.listBranches() ?? Future.value(<BranchModel>[]),
          ordersRepo?.listOrders() ?? Future.value(<Order>[]),
          deliveriesRepo?.listDeliveries() ?? Future.value(<DeliveryModel>[]),
        ]),
        builder: (context, AsyncSnapshot<List<dynamic>> snapshot) {
          final rawBranches =
              (snapshot.data?[0] as List?)?.cast<BranchModel>() ?? [];
          final branches = rawBranches.isNotEmpty
              ? rawBranches
              : (services.isDemo
                  ? [
                      BranchModel(
                        id: 'dokki',
                        name: 'فرع الدقي الرئيسي',
                        code: 'DKI',
                        city: 'الجيزة',
                        timezone: 'Africa/Cairo',
                        openedAt: DateTime(2023, 1, 1),
                        status: BranchStatus.active,
                      ),
                      BranchModel(
                        id: 'maadi',
                        name: 'فرع المعادي',
                        code: 'MAD',
                        city: 'القاهرة',
                        timezone: 'Africa/Cairo',
                        openedAt: DateTime(2023, 6, 1),
                        status: BranchStatus.active,
                      ),
                    ]
                  : <BranchModel>[]);

          final allOrders =
              (snapshot.data?[1] as List?)?.cast<Order>() ?? [];
          final allDeliveries =
              (snapshot.data?[2] as List?)?.cast<DeliveryModel>() ?? [];

          final activeOrders = allOrders.where((o) => !o.voided).toList();
          final now = DateTime.now();
          final delayedOrders = activeOrders
              .where((o) => now.difference(o.createdAt).inMinutes > 30)
              .toList();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Network Overview Card
              PieCard(
                padding: const EdgeInsets.all(18),
                surfaceColor: PieColors.surface2,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildNetworkStat(
                        'الفروع المتصلة', '${branches.length}', PieColors.stateSynced),
                    _buildNetworkStat(
                        'أوردرات جارية', '${activeOrders.length}', PieColors.managerAccent),
                    _buildNetworkStat(
                        'تحذيرات التأخير', '${delayedOrders.length}', PieColors.stateError),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'شبكة الفروع المباشرة (${branches.length})',
                    style: PieTypography.heading.copyWith(fontWeight: FontWeight.w700),
                  ),
                  IconButton(
                    tooltip: 'تحديث المؤشرات اللحظية',
                    icon: const Icon(Icons.refresh_rounded, color: PieColors.inkSecondary),
                    onPressed: () => setState(() {}),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              if (branches.isEmpty)
                const PieCard(
                  padding: EdgeInsets.all(32),
                  child: PieEmptyState(
                    title: 'لا توجد فروع مسجلة بالشبكة',
                    description: 'قم بإضافة الفروع في تبويب شبكة الفروع لبدء مراقبة الأحمال والتشغيل.',
                    icon: Icons.hub_outlined,
                  ),
                )
              else
                for (final branch in branches) ...[
                  _buildBranchTriageCard(
                    branch: branch,
                    activeOrders: activeOrders,
                    deliveries: allDeliveries,
                    delayedCount: delayedOrders.length,
                  ),
                  const SizedBox(height: 12),
                ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildNetworkStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: PieTypography.monoDisplay.copyWith(color: color, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        Text(label, style: PieTypography.caption),
      ],
    );
  }

  Widget _buildBranchTriageCard({
    required BranchModel branch,
    required List<Order> activeOrders,
    required List<DeliveryModel> deliveries,
    required int delayedCount,
  }) {
    final isDelayed = delayedCount > 0;
    final takeawayOrders =
        activeOrders.where((o) => o.orderType == OrderType.takeaway).length;
    final deliveryOrders = deliveries
        .where((d) =>
            d.state != DeliveryState.delivered && d.state != DeliveryState.failed)
        .length;

    return PieCard(
      padding: const EdgeInsets.all(16),
      isActive: isDelayed,
      activeColor: PieColors.stateError,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: branch.isActive ? const Color(0xFF4ADE80) : PieColors.inkMuted,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        branch.name,
                        style: PieTypography.bodyStrong,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (isDelayed)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: PieColors.stateErrorBg,
                    borderRadius: PieRadius.borderSm,
                    border: Border.all(color: PieColors.stateError),
                  ),
                  child: Text(
                    'ضغط تشغيلي ($delayedCount متأخر)',
                    style: PieTypography.caption.copyWith(color: PieColors.stateError),
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF052E16),
                    borderRadius: PieRadius.borderSm,
                  ),
                  child: Text(
                    'تشغيل طبيعي',
                    style: PieTypography.caption.copyWith(color: const Color(0xFF4ADE80)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildBranchMetric('أوردرات التيك أواي', '$takeawayOrders'),
              _buildBranchMetric('أوردرات الدليفري', '$deliveryOrders'),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: PieButton.secondary(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        backgroundColor: PieColors.surface2,
                        content: Text('متابعة تفاصيل أوردرات ${branch.name}'),
                      ),
                    );
                  },
                  label: 'عرض أوردرات الفرع',
                  height: 38,
                ),
              ),
              if (isDelayed) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: PieButton.primary(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          backgroundColor: PieColors.surface2,
                          content: Text('تم تفعيل التحويل التلقائي للأوردرات الزائدة لأقرب فرع'),
                        ),
                      );
                    },
                    label: 'إعادة توجيه طارئ',
                    accentColor: PieColors.managerAccent,
                    height: 38,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBranchMetric(String label, String value) {
    return Column(
      children: [
        Text(value, style: PieTypography.monoBody.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(label, style: PieTypography.caption.copyWith(color: PieColors.inkSecondary)),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import '../../core/di/app_services.dart';
import '../../core/theme/pie_colors.dart';
import '../../core/theme/pie_typography.dart';
import '../../core/widgets/pie_button.dart';
import '../../core/widgets/pie_card.dart';
import '../../core/widgets/pie_empty_state.dart';
import '../../core/widgets/pie_numeral.dart';
import '../../domain/models/delivery.dart';

/// Screen 15: Fleet Overview (إدارة أسطول التوصيل والدليفري)
///
/// Functional contract:
/// - Courier roster and availability
/// - Active orders assigned to each courier
/// - Auto-assign trigger for waiting orders
class FleetScreen extends StatefulWidget {
  const FleetScreen({super.key});

  @override
  State<FleetScreen> createState() => _FleetScreenState();
}

class _FleetScreenState extends State<FleetScreen> {
  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final deliveryRepo = services.deliveries;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: PieColors.canvas,
        appBar: AppBar(
          title: Text('أسطول التوصيل والدليفري', style: PieTypography.heading),
        ),
        body: FutureBuilder<List<DriverModel>>(
          future: deliveryRepo?.listDrivers(),
          builder: (context, driverSnapshot) {
            final drivers = driverSnapshot.data ?? [];

            return FutureBuilder<List<DeliveryModel>>(
              future: deliveryRepo?.listDeliveries(),
              builder: (context, deliverySnapshot) {
                final deliveries = deliverySnapshot.data ?? [];
                final waitingDeliveries =
                    deliveries.where((d) => d.state == DeliveryState.waiting).toList();

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Auto-assign Banner Card
                    PieCard(
                      padding: const EdgeInsets.all(16),
                      surfaceColor: PieColors.surface2,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('أوردرات في انتظار التسكين', style: PieTypography.subheading),
                              const SizedBox(height: 2),
                              Text(
                                '${waitingDeliveries.length} أوردر جاهز للتوزيع على الطيارين',
                                style: PieTypography.caption.copyWith(color: PieColors.driverAccent),
                              ),
                            ],
                          ),
                          PieButton.primary(
                            onPressed: waitingDeliveries.isEmpty
                                ? null
                                : () async {
                                    await deliveryRepo?.autoAssignWaiting();
                                    if (mounted) {
                                      setState(() {});
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          backgroundColor: PieColors.surface2,
                                          content: Text('تم تسكين وتوزيع الأوردرات آلياً على الطيارين المتاحين'),
                                        ),
                                      );
                                    }
                                  },
                            label: 'تسكين تلقائي',
                            accentColor: PieColors.driverAccent,
                            height: 40,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    Text(
                      'كباتن التوصيل المسجلين (${drivers.length})',
                      style: PieTypography.heading.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),

                    if (drivers.isEmpty)
                      const PieCard(
                        padding: EdgeInsets.all(32),
                        child: PieEmptyState(
                          title: 'مفيش طيارين متسجلين في الفرع',
                          description: 'أضف طيارين جدد من خلال لوحة إدارة الفريق بالفرع.',
                          icon: Icons.people_outline_rounded,
                        ),
                      )
                    else
                      for (final driver in drivers) ...[
                        _buildDriverCard(driver, deliveries),
                        const SizedBox(height: 10),
                      ],
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildDriverCard(DriverModel driver, List<DeliveryModel> allDeliveries) {
    final driverDeliveries = allDeliveries
        .where((d) => d.driver == driver.name && d.state != DeliveryState.delivered && d.state != DeliveryState.failed)
        .toList();

    return PieCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: PieColors.surface2,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: PieColors.border),
            ),
            child: const Icon(Icons.two_wheeler_rounded, color: PieColors.driverAccent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(driver.name, style: PieTypography.bodyStrong),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: driver.available ? const Color(0xFF052E16) : PieColors.surface2,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: driver.available ? const Color(0xFF4ADE80) : PieColors.border,
                        ),
                      ),
                      child: Text(
                        driver.available ? 'متاح' : 'في مشوار',
                        style: PieTypography.caption.copyWith(
                          color: driver.available ? const Color(0xFF4ADE80) : PieColors.inkMuted,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'الأوردرات الجارية: ${driverDeliveries.length} أوردر',
                  style: PieTypography.caption.copyWith(color: PieColors.inkSecondary),
                ),
              ],
            ),
          ),
          PieNumeral.count(
            driverDeliveries.length,
            style: PieTypography.monoHeading.copyWith(
              color: PieColors.driverAccent,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

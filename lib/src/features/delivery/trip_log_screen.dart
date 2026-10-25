import 'package:flutter/material.dart';
import '../../core/di/app_services.dart';
import '../../core/state/sync_monitor.dart';
import '../../core/theme/pie_colors.dart';
import '../../core/theme/pie_typography.dart';
import '../../core/widgets/pie_badge.dart';
import '../../core/widgets/pie_card.dart';
import '../../core/widgets/pie_empty_state.dart';
import '../../core/widgets/pie_numeral.dart';
import '../../domain/models/delivery.dart';
import 'driver_identity_service.dart';

/// Screen 14: Delivery Log & Daily Archive (سجل التوصيل والأرشيف اليومي للطيار)
///
/// Functional contract:
/// - Daily delivery archive
/// - Total delivered, failed, and collected stats
/// - Detailed stop history
class TripLogScreen extends StatefulWidget {
  const TripLogScreen({super.key});

  @override
  State<TripLogScreen> createState() => _TripLogScreenState();
}

class _TripLogScreenState extends State<TripLogScreen> {
  DeliveryState? _selectedFilter;

  @override
  void initState() {
    super.initState();
    SyncMonitor.instance.addListener(_onSyncRefresh);
  }

  @override
  void dispose() {
    SyncMonitor.instance.removeListener(_onSyncRefresh);
    super.dispose();
  }

  void _onSyncRefresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final deliveryRepo = services.deliveries;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: FutureBuilder<List<dynamic>>(
          future: Future.wait([
            deliveryRepo?.listDrivers() ?? Future.value(<DriverModel>[]),
            deliveryRepo?.listDeliveries() ?? Future.value(<DeliveryModel>[]),
          ]),
          builder: (context, snapshot) {
            final drivers = (snapshot.data?[0] as List<DriverModel>?) ?? [];
            final allDeliveries = (snapshot.data?[1] as List<DeliveryModel>?) ?? [];

            final myDeliveries = allDeliveries
                .where((d) => DriverSession.instance.isDeliveryAssignedToCurrentDriver(
                      delivery: d,
                      user: services.auth.currentUser,
                      drivers: drivers,
                    ))
                .toList();
            final deliveredList = myDeliveries
                .where((d) => d.state == DeliveryState.delivered)
                .toList();
            final failedList = myDeliveries
                .where((d) =>
                    d.state == DeliveryState.failed ||
                    d.state == DeliveryState.returned)
                .toList();

            final totalCollected =
                deliveredList.fold(0.0, (sum, d) => sum + d.amount);

            var filtered = myDeliveries;
            if (_selectedFilter != null) {
              if (_selectedFilter == DeliveryState.failed) {
                filtered = filtered
                    .where((d) =>
                        d.state == DeliveryState.failed ||
                        d.state == DeliveryState.returned)
                    .toList();
              } else {
                filtered =
                    filtered.where((d) => d.state == _selectedFilter).toList();
              }
            }

            return RefreshIndicator(
              onRefresh: () async {
                await services.sync?.requestSync();
                if (mounted) setState(() {});
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  // Daily KPI summary
                PieCard(
                  padding: const EdgeInsets.all(18),
                  surfaceColor: PieColors.surface2,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildSummaryItem('اتسلّم', deliveredList.length, const Color(0xFF4ADE80)),
                      _buildSummaryItem('تعذر / مرتجع', failedList.length, PieColors.stateError),
                      Column(
                        children: [
                          PieNumeral.money(
                            totalCollected,
                            style: PieTypography.monoHeading.copyWith(
                              color: PieColors.driverAccent,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text('إجمالي النقدية المحصلة', style: PieTypography.caption),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Filter chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterChip(null, 'الكل (${myDeliveries.length})'),
                      const SizedBox(width: 6),
                      _buildFilterChip(DeliveryState.delivered, 'اتسلّم (${deliveredList.length})'),
                      const SizedBox(width: 6),
                      _buildFilterChip(DeliveryState.failed, 'تعذر التسليم (${failedList.length})'),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Deliveries List
                if (filtered.isEmpty)
                  const PieEmptyState(
                    title: 'مفيش أوردرات في السجل ده',
                    description: 'كل الأوردرات المكتملة أو المتعثرة هتتسجل هنا بتوقيتاتها.',
                    icon: Icons.history_rounded,
                  )
                else
                  for (final delivery in filtered) ...[
                    PieCard(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'أوردر #${delivery.orderRef}',
                                style: PieTypography.bodyStrong.copyWith(fontWeight: FontWeight.w700),
                              ),
                              PieBadge.deliveryState(delivery.state),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            delivery.address,
                            style: PieTypography.body.copyWith(color: PieColors.inkSecondary),
                          ),
                          if (delivery.failedReason != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              'سبب التعذر: ${delivery.failedReason!.label}',
                              style: PieTypography.caption.copyWith(color: PieColors.stateError),
                            ),
                          ],
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${delivery.createdAt.hour.toString().padLeft(2, '0')}:${delivery.createdAt.minute.toString().padLeft(2, '0')}',
                                style: PieTypography.monoCaption,
                              ),
                              PieNumeral.money(
                                delivery.amount,
                                style: PieTypography.monoBody.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: delivery.state == DeliveryState.delivered
                                      ? PieColors.driverAccent
                                      : PieColors.inkMuted,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
              ],
            ),
          );
        },
        ),
    );
  }

  Widget _buildSummaryItem(String label, int count, Color color) {
    return Column(
      children: [
        PieNumeral.count(
          count,
          style: PieTypography.monoHeading.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(label, style: PieTypography.caption),
      ],
    );
  }

  Widget _buildFilterChip(DeliveryState? state, String label) {
    final isSelected = _selectedFilter == state;

    return FilterChip(
      label: Text(label),
      selected: isSelected,
      backgroundColor: PieColors.surface1,
      selectedColor: PieColors.driverSurface,
      side: BorderSide(
        color: isSelected ? PieColors.driverAccent : PieColors.border,
      ),
      labelStyle: PieTypography.caption.copyWith(
        color: isSelected ? PieColors.driverAccent : PieColors.inkSecondary,
        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
      ),
      onSelected: (_) => setState(() => _selectedFilter = state),
    );
  }
}

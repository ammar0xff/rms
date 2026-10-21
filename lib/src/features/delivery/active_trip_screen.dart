import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/di/app_services.dart';
import '../../core/theme/pie_colors.dart';
import '../../core/theme/pie_radius.dart';
import '../../core/theme/pie_typography.dart';
import '../../core/widgets/pie_badge.dart';
import '../../core/widgets/pie_button.dart';
import '../../core/widgets/pie_card.dart';
import '../../core/widgets/pie_empty_state.dart';
import '../../core/widgets/pie_numeral.dart';
import '../../domain/models/collection.dart';
import '../../domain/models/delivery.dart';
import '../../core/sound/pie_sound_service.dart';
import 'driver_fail_dialog.dart';
import 'driver_identity_service.dart';
import 'driver_nav_sheet.dart';
import 'driver_receipt_sheet.dart';

/// Screen 9: Active Trip Screen (قائمة الأوردرات ومسار الطلعة النشطة)
///
/// Functional contract:
/// - Trip header (courier name, total cash custody, active stops)
/// - Four-phase progress indicator
/// - Numbered stops with the current stop expanded
/// - Start-route call to action
/// - Per-stop actions (Call customer, navigate, receipt, deliver, fail)
class ActiveTripScreen extends StatefulWidget {
  const ActiveTripScreen({super.key});

  @override
  State<ActiveTripScreen> createState() => _ActiveTripScreenState();
}

class _ActiveTripScreenState extends State<ActiveTripScreen> {
  String? _expandedStopId;

  Future<void> _callPhone(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final deliveryRepo = services.deliveries;

    if (deliveryRepo == null) {
      return const PieEmptyState(
        title: 'نظام الدليفري غير متاح',
        description: 'اتأكد من تهيئة قاعدة البيانات المحلية على الجهاز.',
        icon: Icons.error_outline_rounded,
      );
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: FutureBuilder<List<dynamic>>(
        future: Future.wait([
          deliveryRepo.listDrivers(),
          deliveryRepo.listDeliveries(),
        ]),
        builder: (context, snapshot) {
          final drivers = (snapshot.data?[0] as List<DriverModel>?) ?? [];
          final allDeliveries = (snapshot.data?[1] as List<DeliveryModel>?) ?? [];
          final myDriverName = DriverSession.instance.resolveCurrentDriverName(
            user: services.auth.currentUser,
            drivers: drivers,
          );

          final myDeliveries =
              allDeliveries.where((d) => d.driver == myDriverName).toList();
          final activeDeliveries = myDeliveries
              .where((d) =>
                  d.state != DeliveryState.delivered &&
                  d.state != DeliveryState.failed)
              .toList();

          final totalCustody = myDeliveries
              .where((d) =>
                  d.state == DeliveryState.delivered &&
                  d.settlementStatus != SettlementStatus.settled)
              .fold(0.0, (sum, d) => sum + d.amount);

          if (activeDeliveries.isEmpty) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildTripHeader(myDriverName, activeDeliveries.length, totalCustody),
                const SizedBox(height: 20),
                const PieCard(
                  padding: EdgeInsets.all(32),
                  child: PieEmptyState(
                    title: 'مفيش طلعات نشطة دلوقتي',
                    description: 'كل الأوردرات المسندة ليك هتظهر هنا بمجرد تجهيزها من الفرع.',
                    icon: Icons.two_wheeler_outlined,
                  ),
                ),
              ],
            );
          }

          // Auto-expand first open stop if none expanded
          _expandedStopId ??= activeDeliveries.first.id;

          final isOnRoute = activeDeliveries.any((d) => d.state == DeliveryState.onRoute);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Trip Header
              _buildTripHeader(myDriverName, activeDeliveries.length, totalCustody),
              const SizedBox(height: 16),

              // Four-phase progress indicator
              _buildFourPhaseProgress(isOnRoute),
              const SizedBox(height: 16),

              // Start Route CTA if not yet on route
              if (!isOnRoute) ...[
                PieButton.primary(
                  onPressed: () async {
                    for (final d in activeDeliveries) {
                      await deliveryRepo.updateState(d.id, DeliveryState.onRoute);
                    }
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          backgroundColor: PieColors.surface2,
                          content: Text('بدأت الطلعة! تم تحديث حالة الأوردرات إلى "في الطريق"'),
                        ),
                      );
                    }
                  },
                  label: 'بدء خط السير والتحرك بالطلعة',
                  icon: Icons.play_arrow_rounded,
                  accentColor: PieColors.driverAccent,
                  height: 52,
                ),
                const SizedBox(height: 16),
              ],

              // Numbered Stops
              Text(
                'محطات التوصيل (${activeDeliveries.length})',
                style: PieTypography.heading.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),

              for (var i = 0; i < activeDeliveries.length; i++) ...[
                _buildStopCard(
                  delivery: activeDeliveries[i],
                  stopNumber: i + 1,
                  isExpanded: activeDeliveries[i].id == _expandedStopId,
                ),
                const SizedBox(height: 12),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildTripHeader(String driverName, int stopsCount, double custody) {
    return PieCard(
      padding: const EdgeInsets.all(18),
      surfaceColor: PieColors.surface2,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: PieColors.driverSurface,
                    borderRadius: PieRadius.borderMd,
                    border: Border.all(color: PieColors.driverBorder),
                  ),
                  child: const Icon(
                    Icons.two_wheeler_rounded,
                    color: PieColors.driverAccent,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'الطيار: $driverName',
                        style: PieTypography.bodyStrong,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$stopsCount محطات توصيل متبقية',
                        style: PieTypography.caption.copyWith(color: PieColors.inkSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('العهدة المحصلة:', style: PieTypography.caption),
              const SizedBox(height: 2),
              PieNumeral.money(
                custody,
                style: PieTypography.monoHeading.copyWith(
                  color: PieColors.driverAccent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFourPhaseProgress(bool isOnRoute) {
    final phases = [
      ('بالفرع', true),
      ('استلام', true),
      ('في الطريق', isOnRoute),
      ('تسليم', false),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: PieColors.surface1,
        borderRadius: PieRadius.borderMd,
        border: Border.all(color: PieColors.border),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(phases.length, (index) {
            final phase = phases[index];
            final isPassed = phase.$2;

            return Padding(
              padding: EdgeInsets.only(left: index < phases.length - 1 ? 14 : 0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: isPassed ? PieColors.driverAccent : PieColors.surface2,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isPassed ? PieColors.driverAccent : PieColors.border,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: isPassed ? Colors.black : PieColors.inkMuted,
                      ),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    phase.$1,
                    style: PieTypography.caption.copyWith(
                      color: isPassed ? PieColors.ink : PieColors.inkMuted,
                      fontWeight: isPassed ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildStopCard({
    required DeliveryModel delivery,
    required int stopNumber,
    required bool isExpanded,
  }) {
    final services = AppScope.of(context);

    return PieCard(
      padding: const EdgeInsets.all(16),
      isActive: isExpanded,
      activeColor: PieColors.driverAccent,
      onTap: () => setState(() => _expandedStopId = delivery.id),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Stop Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: isExpanded ? PieColors.driverAccent : PieColors.surface2,
                        shape: BoxShape.circle,
                        border: Border.all(color: PieColors.border),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '$stopNumber',
                        style: PieTypography.monoBody.copyWith(
                          color: isExpanded ? Colors.black : PieColors.ink,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'أوردر #${delivery.orderRef}',
                        style: PieTypography.bodyStrong.copyWith(fontWeight: FontWeight.w700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PieBadge.deliveryState(delivery.state),
                  const SizedBox(width: 6),
                  Icon(
                    isExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                    color: PieColors.inkSecondary,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Address & Amount preview
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  delivery.address,
                  style: PieTypography.body.copyWith(color: PieColors.inkSecondary),
                  maxLines: isExpanded ? 3 : 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              PieNumeral.money(
                delivery.amount,
                style: PieTypography.monoHeading.copyWith(
                  color: PieColors.driverAccent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),

          // Expanded Content
          if (isExpanded) ...[
            const Divider(color: PieColors.border, height: 24),
            // Landmark & Customer Info
            Row(
              children: [
                const Icon(Icons.phone_in_talk_rounded, size: 16, color: PieColors.driverAccent),
                const SizedBox(width: 6),
                Text('العميل: ', style: PieTypography.caption.copyWith(color: PieColors.inkSecondary)),
                Expanded(
                  child: Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text(
                      '01012345678',
                      style: PieTypography.monoBody.copyWith(fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                PieButton.ghost(
                  onPressed: () => _callPhone('01012345678'),
                  label: 'اتصال',
                  icon: Icons.phone_rounded,
                  height: 36,
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Per-Stop Action Buttons (Ergonomic 2x2 layout)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: PieButton.primary(
                        onPressed: () => DriverNavSheet.show(context, delivery: delivery),
                        label: 'الملاحة وخريطة السير',
                        icon: Icons.navigation_rounded,
                        accentColor: PieColors.driverAccent,
                        height: 40,
                      ),
                    ),
                    const SizedBox(width: 8),
                    PieButton.secondary(
                      onPressed: () => DriverReceiptSheet.show(context, delivery: delivery),
                      label: 'عرض البون',
                      icon: Icons.receipt_long_rounded,
                      height: 40,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: PieButton.primary(
                        onPressed: () async {
                          await services.deliveries?.updateState(delivery.id, DeliveryState.delivered);
                          await services.deliveries?.recordCollection(
                            deliveryId: delivery.id,
                            amount: delivery.amount,
                            createdOffline: services.sync?.isOnline != true,
                          );
                          PieSoundService.instance.chime();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('تم تسليم الأوردر بنجاح وإيداع الكاش بالعهدة'),
                              ),
                            );
                          }
                        },
                        label: 'تم التسليم بنجاح',
                        icon: Icons.check_circle_outline_rounded,
                        accentColor: const Color(0xFF10B981),
                        height: 42,
                      ),
                    ),
                    const SizedBox(width: 8),
                    PieButton.destructive(
                      onPressed: () => DriverFailDialog.show(context, delivery: delivery),
                      label: 'تعذر التسليم',
                      icon: Icons.cancel_outlined,
                      height: 42,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

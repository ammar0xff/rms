import 'package:flutter/material.dart';
import '../../core/di/app_services.dart';
import '../../core/theme/pie_colors.dart';
import '../../core/theme/pie_typography.dart';
import '../../core/widgets/pie_button.dart';
import '../../core/widgets/pie_card.dart';
import '../../core/widgets/pie_numeral.dart';
import '../../domain/models/delivery.dart';
import 'driver_fail_dialog.dart';

/// Screen 10: Driver Navigation Sheet (توصيل وملاحة الدليفري)
///
/// Functional contract:
/// - Next turn guidance card
/// - Huge collection reminder
/// - Arrived / Failed actions
/// - Honest local GPS log note
class DriverNavSheet extends StatelessWidget {
  const DriverNavSheet({super.key, required this.delivery});

  final DeliveryModel delivery;

  static Future<void> show(BuildContext context, {required DeliveryModel delivery}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: PieColors.surfaceOverlay,
      builder: (context) => DriverNavSheet(delivery: delivery),
    );
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top handle & Title
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const Icon(Icons.navigation_rounded, color: PieColors.driverAccent, size: 22),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'ملاحة خط السير • أوردر #${delivery.orderRef}',
                          style: PieTypography.heading,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: PieColors.inkSecondary),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Next Turn Card
            PieCard(
              padding: const EdgeInsets.all(16),
              surfaceColor: PieColors.surface2,
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: PieColors.driverSurface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: PieColors.driverBorder),
                    ),
                    child: const Icon(
                      Icons.turn_right_rounded,
                      size: 28,
                      color: PieColors.driverAccent,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('انعطف يميناً بعد 250 متراً', style: PieTypography.bodyStrong),
                        const SizedBox(height: 2),
                        Text(
                          'باتجاه شارع التحرير - العمارة على ناصية الشارع',
                          style: PieTypography.caption.copyWith(color: PieColors.inkSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Huge Collection Reminder
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: PieColors.driverSurface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: PieColors.driverBorder, width: 1.5),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.payments_rounded, color: PieColors.driverAccent, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'تذكير استلام النقدية (كاش عند الباب):',
                        style: PieTypography.subheading.copyWith(
                          color: PieColors.ink,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  PieNumeral.money(
                    delivery.amount,
                    style: PieTypography.monoDisplay.copyWith(
                      color: PieColors.driverAccent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Honest Local GPS Log Note
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.gps_fixed_rounded, size: 13, color: PieColors.inkMuted),
                const SizedBox(width: 6),
                Text(
                  'يتم تسجيل وقت ومسار الوصول محلياً في سجل الجهاز (Local Log)',
                  style: PieTypography.caption.copyWith(color: PieColors.inkMuted),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  flex: 6,
                  child: PieButton.primary(
                    onPressed: () async {
                      await services.deliveries?.updateState(delivery.id, DeliveryState.delivered);
                      await services.deliveries?.recordCollection(
                        deliveryId: delivery.id,
                        amount: delivery.amount,
                        createdOffline: services.sync?.isOnline != true,
                      );
                      if (context.mounted) {
                        Navigator.of(context).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            backgroundColor: PieColors.surface2,
                            content: Text('تم تأكيد تسليم الأوردر وتسجيل المبلغ بالعهدة'),
                          ),
                        );
                      }
                    },
                    label: 'وصلت وتم التسليم',
                    icon: Icons.check_circle_rounded,
                    accentColor: PieColors.driverAccent,
                    height: 50,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 4,
                  child: PieButton.destructive(
                    onPressed: () async {
                      Navigator.of(context).pop();
                      await DriverFailDialog.show(context, delivery: delivery);
                    },
                    label: 'تعذر التسليم',
                    icon: Icons.cancel_outlined,
                    height: 50,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

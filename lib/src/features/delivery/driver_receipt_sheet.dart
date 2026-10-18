import 'package:flutter/material.dart';
import '../../core/di/app_services.dart';
import '../../core/theme/pie_colors.dart';
import '../../core/theme/pie_typography.dart';
import '../../core/widgets/pie_card.dart';
import '../../core/widgets/pie_numeral.dart';
import '../../domain/models/delivery.dart';
import '../../domain/models/order.dart';

/// Screen 12: Delivery Receipt Sheet (تفاصيل بون التوصيل والفاتورة)
///
/// Functional contract:
/// - Order lines and quantities
/// - Modifiers and kitchen notes
/// - Delivery address and landmark
/// - Totals to collect
class DriverReceiptSheet extends StatelessWidget {
  const DriverReceiptSheet({super.key, required this.delivery});

  final DeliveryModel delivery;

  static Future<void> show(BuildContext context, {required DeliveryModel delivery}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: PieColors.surfaceOverlay,
      builder: (context) => DriverReceiptSheet(delivery: delivery),
    );
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('بون توصيل أوردر #${delivery.orderRef}', style: PieTypography.heading),
                    const SizedBox(height: 4),
                    Text(
                      'المبلغ المطلوب تحصيله كاش',
                      style: PieTypography.caption.copyWith(color: PieColors.driverAccent),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: PieColors.inkSecondary),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Landmark & Address Card
            PieCard(
              padding: const EdgeInsets.all(14),
              surfaceColor: PieColors.surface2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.location_on_outlined, size: 18, color: PieColors.driverAccent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          delivery.address,
                          style: PieTypography.bodyStrong,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'العلامة المميزة: بجوار محطة المترو - عمارة 14 الدور 3',
                    style: PieTypography.caption.copyWith(color: PieColors.inkSecondary),
                  ),
                ],
              ),
            ),
            const Divider(color: PieColors.border, height: 24),

            // Order Lines
            Expanded(
              child: FutureBuilder<Order?>(
                future: services.orders?.listOrders().then((orders) {
                  try {
                    return orders.firstWhere(
                      (o) =>
                          o.canonicalOrderNumber == delivery.orderRef ||
                          o.provisionalOrderNumber == delivery.orderRef ||
                          o.localId == delivery.orderRef,
                    );
                  } catch (_) {
                    return null;
                  }
                }),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(strokeWidth: 2, color: PieColors.driverAccent),
                          SizedBox(height: 12),
                          Text('جاري استرجاع أصناف الأوردر...', style: PieTypography.body),
                        ],
                      ),
                    );
                  }

                  final order = snapshot.data;
                  if (order == null || order.items.isEmpty) {
                    return Center(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: PieColors.surface2,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: PieColors.border),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.receipt_long_rounded,
                              size: 40,
                              color: PieColors.driverAccent,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'أوردر رقم #${delivery.orderRef}',
                              style: PieTypography.bodyStrong,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'تفاصيل الأصناف مسجلة على فاتورة المطبخ الورقية المرفقة بالطلب.',
                              textAlign: TextAlign.center,
                              style: PieTypography.caption.copyWith(color: PieColors.inkSecondary),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'العنوان: ${delivery.address}',
                              textAlign: TextAlign.center,
                              style: PieTypography.caption.copyWith(color: PieColors.inkMuted),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return ListView.separated(
                    itemCount: order.items.length,
                    separatorBuilder: (_, __) => const Divider(color: PieColors.border, height: 1),
                    itemBuilder: (context, index) {
                      final item = order.items[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('${item.quantity}x ${item.name}', style: PieTypography.bodyStrong),
                                PieNumeral.money(item.unitPrice * item.quantity),
                              ],
                            ),
                            if (item.modifiers.isNotEmpty)
                              Text(
                                item.modifiers.join(' • '),
                                style: PieTypography.caption.copyWith(color: PieColors.driverAccent),
                              ),
                            if (item.note != null)
                              Text('ملاحظة: ${item.note}', style: PieTypography.caption),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            const Divider(color: PieColors.border, height: 20),

            // Total Collection Amount Hero
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: PieColors.driverSurface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: PieColors.driverBorder),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'إجمالي التحصيل كاش:',
                    style: PieTypography.subheading.copyWith(fontWeight: FontWeight.w700),
                  ),
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
          ],
        ),
      ),
    );
  }
}

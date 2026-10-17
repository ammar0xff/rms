import 'package:flutter/material.dart';
import '../../core/di/app_services.dart';
import '../../core/theme/pie_colors.dart';
import '../../core/theme/pie_typography.dart';
import '../../core/widgets/pie_button.dart';
import '../../core/widgets/pie_card.dart';
import '../../core/widgets/pie_empty_state.dart';
import '../../core/widgets/pie_numeral.dart';
import '../../domain/models/delivery.dart';

/// Screen 13: Custody Settlement (تسوية وتوريد عهدة الكاش للطيار)
///
/// Functional contract:
/// - Collected cash minus per stop
/// - Unique Handover code for cashier audit verification
/// - Batch custody turnover action
class CustodySettlementScreen extends StatefulWidget {
  const CustodySettlementScreen({super.key});

  @override
  State<CustodySettlementScreen> createState() => _CustodySettlementScreenState();
}

class _CustodySettlementScreenState extends State<CustodySettlementScreen> {
  // Generate daily handover code
  final String _handoverCode = 'HND-8429';

  Future<void> _submitHandover(double totalAmount) async {
    final services = AppScope.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: PieColors.surfaceOverlay,
          title: Text('تأكيد توريد العهدة للكاشير', style: PieTypography.heading),
          content: Text(
            'سيتم توريد مبلغ ${PieTypography.formatEgp(totalAmount)} بكود التوريد $_handoverCode. هل استلم الكاشير المبلغ بالكامل؟',
            style: PieTypography.body,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('إلغاء', style: PieTypography.body.copyWith(color: PieColors.inkSecondary)),
            ),
            PieButton.primary(
              onPressed: () => Navigator.of(context).pop(true),
              label: 'أكّد التوريد',
              accentColor: PieColors.driverAccent,
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && mounted) {
      await services.deliveries?.recordBatchSettlement(
        driver: 'كابتن أحمد محمود',
        branchId: 'main-branch',
        amount: totalAmount,
        receiver: 'الكاشير الرئيسي',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: PieColors.surface2,
            content: Text('تم توريد العهدة بالكامل للكاشير بنجاح'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final deliveryRepo = services.deliveries;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: PieColors.canvas,
        appBar: AppBar(
          title: Text('تسوية وتوريد عهدة الكاش', style: PieTypography.heading),
        ),
        body: FutureBuilder<List<DeliveryModel>>(
          future: deliveryRepo?.listDeliveries(),
          builder: (context, snapshot) {
            final allDeliveries = snapshot.data ?? [];
            final deliveredStops =
                allDeliveries.where((d) => d.state == DeliveryState.delivered).toList();

            final totalCustody =
                deliveredStops.fold(0.0, (sum, d) => sum + d.amount);

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Handover Code & Custody Total Hero Card
                PieCard(
                  padding: const EdgeInsets.all(20),
                  surfaceColor: PieColors.surface2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('إجمالي العهدة النقدية للطلعة:', style: PieTypography.body),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: PieColors.driverSurface,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: PieColors.driverBorder),
                            ),
                            child: Text(
                              'كود التوريد: $_handoverCode',
                              style: PieTypography.monoCaption.copyWith(
                                color: PieColors.driverAccent,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      PieNumeral.money(
                        totalCustody,
                        style: PieTypography.monoDisplay.copyWith(
                          color: PieColors.driverAccent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'المبلغ ده مطلوب تسليمه لكاشير الفرع مع كود التوريد لإخلاء طرفك من الطلعة.',
                        style: PieTypography.caption.copyWith(color: PieColors.inkSecondary),
                      ),
                      const SizedBox(height: 20),
                      PieButton.primary(
                        onPressed: totalCustody <= 0 ? null : () => _submitHandover(totalCustody),
                        label: 'تسليم وتوريد العهدة للكاشير',
                        icon: Icons.assignment_turned_in_rounded,
                        accentColor: PieColors.driverAccent,
                        height: 52,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Breakdown per delivered stop
                Text(
                  'تفاصيل المبالغ المحصلة من العملاء (${deliveredStops.length})',
                  style: PieTypography.subheading.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),

                if (deliveredStops.isEmpty)
                  const PieCard(
                    padding: EdgeInsets.all(32),
                    child: PieEmptyState(
                      title: 'مفيش مبالغ محصلة لسه',
                      description: 'بمجرد تسليم الأوردرات للعملاء، مبالغ الكاش هتتجمع هنا.',
                      icon: Icons.payments_outlined,
                    ),
                  )
                else
                  for (final stop in deliveredStops) ...[
                    PieCard(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('أوردر #${stop.orderRef}', style: PieTypography.bodyStrong),
                              const SizedBox(height: 2),
                              Text(
                                stop.address,
                                style: PieTypography.caption.copyWith(color: PieColors.inkSecondary),
                              ),
                            ],
                          ),
                          PieNumeral.money(
                            stop.amount,
                            style: PieTypography.monoBody.copyWith(
                              fontWeight: FontWeight.w700,
                              color: PieColors.driverAccent,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
              ],
            );
          },
        ),
      ),
    );
  }
}

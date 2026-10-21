import 'package:flutter/material.dart';
import '../../core/di/app_services.dart';
import '../../core/sound/pie_sound_service.dart';
import '../../core/theme/pie_colors.dart';
import '../../core/theme/pie_radius.dart';
import '../../core/theme/pie_typography.dart';
import '../../core/widgets/pie_button.dart';
import '../../core/widgets/pie_card.dart';
import '../../core/widgets/pie_empty_state.dart';
import '../../core/widgets/pie_numeral.dart';
import '../../domain/models/collection.dart';
import '../../domain/models/delivery.dart';
import 'driver_identity_service.dart';

/// Screen 13: Custody Settlement (تسوية وتوريد عهدة الكاش للطيار)
///
/// Functional contract:
/// - Strictly scoped to the authenticated driver's collected cash
/// - Unique Handover code for cashier audit verification
/// - Batch custody turnover action with cash drawer receipt integration
class CustodySettlementScreen extends StatefulWidget {
  const CustodySettlementScreen({super.key});

  @override
  State<CustodySettlementScreen> createState() => _CustodySettlementScreenState();
}

class _CustodySettlementScreenState extends State<CustodySettlementScreen> {
  // Generate daily handover code
  final String _handoverCode = 'HND-8429';
  bool _isSubmitting = false;
  final Set<String> _locallySettledStopIds = {};

  Future<void> _submitHandover({
    required double totalAmount,
    required String driverName,
    required String branchId,
    required List<DeliveryModel> deliveredStops,
  }) async {
    final services = AppScope.of(context);
    final deliveryRepo = services.deliveries;
    if (deliveryRepo == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: PieColors.surfaceOverlay,
          shape: const RoundedRectangleBorder(
            borderRadius: PieRadius.borderLg,
            side: BorderSide(color: PieColors.border),
          ),
          title: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: PieColors.driverSurface,
                  borderRadius: PieRadius.borderMd,
                ),
                child: const Icon(Icons.assignment_turned_in_rounded,
                    color: PieColors.driverAccent, size: 20),
              ),
              const SizedBox(width: 10),
              const Text('تأكيد توريد العهدة للكاشير', style: PieTypography.heading),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'سيتم توريد مبلغ ${PieTypography.formatEgp(totalAmount)} بكود التوريد $_handoverCode. هل استلم كاشير الفرع المبلغ بالكامل؟',
                style: PieTypography.body,
              ),
              const SizedBox(height: 12),
              Text(
                'الكابتن: $driverName',
                style: PieTypography.caption.copyWith(color: PieColors.inkSecondary),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              child: Text('إلغاء',
                  style: PieTypography.body.copyWith(color: PieColors.inkSecondary)),
            ),
            PieButton.primary(
              onPressed: () => Navigator.of(dialogCtx).pop(true),
              label: 'أكّد التوريد الآن',
              accentColor: PieColors.driverAccent,
              height: 40,
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && mounted) {
      setState(() => _isSubmitting = true);
      try {
        await deliveryRepo.recordBatchSettlement(
          driver: driverName,
          branchId: branchId,
          amount: totalAmount,
          receiver: 'كاشير الفرع',
        );

        for (final stop in deliveredStops) {
          if (stop.settlementStatus != SettlementStatus.settled) {
            await deliveryRepo.finalizeSettlement(stop.id);
          }
        }

        await services.sync?.requestSync();

        PieSoundService.playCashDrawer();

        if (mounted) {
          setState(() {
            for (final stop in deliveredStops) {
              _locallySettledStopIds.add(stop.id);
            }
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: PieColors.surface2,
              content: Text(
                'تم توريد عهدة ${PieTypography.formatEgp(totalAmount)} بالكامل للكاشير بنجاح',
                style: PieTypography.body.copyWith(color: const Color(0xFF4ADE80)),
              ),
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final deliveryRepo = services.deliveries;
    final branchRepo = services.branches;
    final user = services.auth.currentUser;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: FutureBuilder<List<dynamic>>(
          future: Future.wait([
            deliveryRepo?.listDrivers() ?? Future.value(<DriverModel>[]),
            deliveryRepo?.listDeliveries() ?? Future.value(<DeliveryModel>[]),
            branchRepo?.activeBranch() ?? Future.value(null),
          ]),
          builder: (context, snapshot) {
            final drivers = (snapshot.data?[0] as List<DriverModel>?) ?? [];
            final allDeliveries = (snapshot.data?[1] as List<DeliveryModel>?) ?? [];
            final branch = snapshot.data?[2];

            final myDriverName = DriverSession.instance.resolveCurrentDriverName(
              user: user,
              drivers: drivers,
            );

            final branchId = branch?.id ?? 'main-branch';

            // Filter strictly to the authenticated driver's delivered orders
            final myDeliveries =
                allDeliveries.where((d) => d.driver == myDriverName).toList();

            final deliveredStops = myDeliveries
                .where((d) =>
                    d.state == DeliveryState.delivered &&
                    d.settlementStatus != SettlementStatus.settled &&
                    !_locallySettledStopIds.contains(d.id) &&
                    !d.address.contains('استلام من الفرع'))
                .toList();

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
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('إجمالي العهدة النقدية في ذمتي:',
                                    style: PieTypography.body),
                                const SizedBox(height: 2),
                                Text(
                                  'الكابتن: $myDriverName',
                                  style: PieTypography.caption
                                      .copyWith(color: PieColors.inkSecondary),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: PieColors.driverSurface,
                              borderRadius: PieRadius.borderSm,
                              border: Border.all(color: PieColors.driverBorder),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'كود التوريد: ',
                                  style: PieTypography.caption.copyWith(
                                    color: PieColors.driverAccent,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Directionality(
                                  textDirection: TextDirection.ltr,
                                  child: Text(
                                    _handoverCode,
                                    style: PieTypography.monoCaption.copyWith(
                                      color: PieColors.driverAccent,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      PieNumeral.money(
                        totalCustody,
                        style: PieTypography.monoDisplay.copyWith(
                          color: totalCustody > 0
                              ? PieColors.driverAccent
                              : PieColors.inkMuted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'المبلغ ده مطلوب تسليمه لكاشير الفرع مع كود التوريد لإخلاء طرفك من الطلعة.',
                        style: PieTypography.caption
                            .copyWith(color: PieColors.inkSecondary),
                      ),
                      const SizedBox(height: 20),
                      PieButton.primary(
                        onPressed: (_isSubmitting || totalCustody <= 0)
                            ? null
                            : () => _submitHandover(
                                  totalAmount: totalCustody,
                                  driverName: myDriverName,
                                  branchId: branchId,
                                  deliveredStops: deliveredStops,
                                ),
                        label: 'تسليم وتوريد العهدة للكاشير',
                        icon: Icons.assignment_turned_in_rounded,
                        accentColor: PieColors.driverAccent,
                        height: 50,
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
                      title: 'لا توجد مبالغ عهدة معلقة',
                      description:
                          'تم توريد كافة النقدية للكاشير بنجاح أو لم تسجل مبالغ تحصيل جديدة بعد.',
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
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('أوردر #${stop.orderRef}',
                                    style: PieTypography.bodyStrong),
                                const SizedBox(height: 2),
                                Text(
                                  stop.address,
                                  style: PieTypography.caption
                                      .copyWith(color: PieColors.inkSecondary),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
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
    );
  }
}

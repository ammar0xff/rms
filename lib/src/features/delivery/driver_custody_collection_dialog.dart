import 'package:flutter/material.dart';
import '../../core/sound/pie_sound_service.dart';
import '../../core/theme/pie_colors.dart';
import '../../core/theme/pie_radius.dart';
import '../../core/theme/pie_typography.dart';
import '../../core/widgets/pie_button.dart';
import '../../core/widgets/pie_numeral.dart';
import '../../domain/models/delivery.dart';

/// Modal dialog for driver cash custody collection on delivery.
/// Requires the driver to explicitly confirm collecting cash from the customer
/// before the order is marked as delivered and deposited into their personal custody.
class DriverCustodyCollectionDialog extends StatelessWidget {
  const DriverCustodyCollectionDialog({
    super.key,
    required this.delivery,
  });

  final DeliveryModel delivery;

  static Future<bool?> show(
    BuildContext context, {
    required DeliveryModel delivery,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DriverCustodyCollectionDialog(delivery: delivery),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        backgroundColor: PieColors.surfaceOverlay,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        shape: const RoundedRectangleBorder(
          borderRadius: PieRadius.borderLg,
          side: BorderSide(color: PieColors.driverBorder, width: 1.5),
        ),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 460),
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: PieColors.driverSurface,
                      shape: BoxShape.circle,
                      border: Border.all(color: PieColors.driverAccent, width: 1.5),
                    ),
                    child: const Icon(
                      Icons.payments_rounded,
                      color: PieColors.driverAccent,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'استلام النقدية وإيداع العهدة',
                          style: PieTypography.heading,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'أوردر رقم #${delivery.orderRef}',
                          style: PieTypography.caption.copyWith(color: PieColors.inkSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // Cash Amount Hero Box
              Container(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
                decoration: BoxDecoration(
                  color: PieColors.surface2,
                  borderRadius: PieRadius.borderMd,
                  border: Border.all(color: PieColors.driverBorder),
                ),
                child: Column(
                  children: [
                    Text(
                      'المبلغ المطلوب تحصيله كاش عند الباب',
                      style: PieTypography.caption.copyWith(
                        color: PieColors.inkSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    PieNumeral.money(
                      delivery.amount,
                      style: PieTypography.monoDisplay.copyWith(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        color: PieColors.driverAccent,
                      ),
                    ),
                    if (delivery.zoneName != null && delivery.zoneName!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        'منطقة: ${delivery.zoneName} (رسوم: ${PieTypography.formatEgp(delivery.zoneFee ?? 0)})',
                        style: PieTypography.caption.copyWith(color: PieColors.inkMuted),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Delivery & Customer Details
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: PieColors.surface1,
                  borderRadius: PieRadius.borderMd,
                  border: Border.all(color: PieColors.border),
                ),
                child: Column(
                  children: [
                    _buildRow(
                      icon: Icons.person_outline_rounded,
                      label: 'العميل:',
                      value: delivery.customerName?.isNotEmpty == true
                          ? delivery.customerName!
                          : 'عميل أوردر #${delivery.orderRef}',
                    ),
                    if (delivery.customerPhone != null && delivery.customerPhone!.isNotEmpty) ...[
                      const Divider(color: PieColors.border, height: 12),
                      _buildRow(
                        icon: Icons.phone_outlined,
                        label: 'الهاتف:',
                        value: delivery.customerPhone!,
                        isLtr: true,
                      ),
                    ],
                    const Divider(color: PieColors.border, height: 12),
                    _buildRow(
                      icon: Icons.location_on_outlined,
                      label: 'العنوان:',
                      value: delivery.address,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Notice Banner
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: PieRadius.borderSm,
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.shield_outlined,
                      size: 18,
                      color: Color(0xFF38BDF8),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'بمجرد التأكيد، سيتم تسجيل هذا المبلغ كعهدة نقدية في ذمتك ككابتن توصيل حتى يتم توريده للكاشير بالفرع.',
                        style: PieTypography.caption.copyWith(
                          color: const Color(0xFFE2E8F0),
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    flex: 6,
                    child: PieButton.primary(
                      onPressed: () {
                        PieSoundService.instance.chime();
                        Navigator.of(context).pop(true);
                      },
                      label: 'استلمت النقدية وأكدت العهدة ✅',
                      icon: Icons.check_circle_rounded,
                      accentColor: const Color(0xFF16A34A),
                      height: 48,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 4,
                    child: PieButton.secondary(
                      onPressed: () {
                        PieSoundService.instance.click();
                        Navigator.of(context).pop(false);
                      },
                      label: 'تراجع',
                      height: 48,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRow({
    required IconData icon,
    required String label,
    required String value,
    bool isLtr = false,
  }) {
    return Row(
      children: [
        Icon(icon, size: 16, color: PieColors.inkSecondary),
        const SizedBox(width: 6),
        Text(
          label,
          style: PieTypography.caption.copyWith(color: PieColors.inkSecondary),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Directionality(
            textDirection: isLtr ? TextDirection.ltr : TextDirection.rtl,
            child: Text(
              value,
              style: PieTypography.bodyStrong.copyWith(fontSize: 13),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: isLtr ? TextAlign.right : TextAlign.start,
            ),
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import '../../core/sound/pie_sound_service.dart';
import '../../core/theme/pie_colors.dart';
import '../../core/theme/pie_radius.dart';
import '../../core/theme/pie_typography.dart';
import '../../core/widgets/pie_badge.dart';
import '../../core/widgets/pie_button.dart';
import '../../core/widgets/pie_numeral.dart';
import '../../domain/models/facility_settings.dart';
import '../../domain/models/order.dart';

/// Clean post-checkout invoice confirmation and direct print modal dialog.
///
/// Gives the cashier:
/// 1. Direct visual receipt verification
/// 2. Guaranteed browser-allowed print button triggered by a direct user gesture
/// 3. Immediate clear option to proceed to the next sale
class PosReceiptSuccessDialog extends StatefulWidget {
  const PosReceiptSuccessDialog({
    super.key,
    required this.order,
    this.facility,
    this.paymentMethod,
    this.paidAmount,
    this.changeDue,
    required this.onPrint,
    this.onOpenTab,
  });

  final Order order;
  final FacilitySettings? facility;
  final String? paymentMethod;
  final double? paidAmount;
  final double? changeDue;
  final Future<void> Function() onPrint;
  final VoidCallback? onOpenTab;

  static Future<void> show(
    BuildContext context, {
    required Order order,
    FacilitySettings? facility,
    String? paymentMethod,
    double? paidAmount,
    double? changeDue,
    required Future<void> Function() onPrint,
    VoidCallback? onOpenTab,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => PosReceiptSuccessDialog(
        order: order,
        facility: facility,
        paymentMethod: paymentMethod,
        paidAmount: paidAmount,
        changeDue: changeDue,
        onPrint: onPrint,
        onOpenTab: onOpenTab,
      ),
    );
  }

  @override
  State<PosReceiptSuccessDialog> createState() => _PosReceiptSuccessDialogState();
}

class _PosReceiptSuccessDialogState extends State<PosReceiptSuccessDialog> {
  bool _isPrinting = false;

  @override
  void initState() {
    super.initState();
    // Play chime sound
    PieSoundService.instance.chime();
  }

  Future<void> _handlePrint() async {
    setState(() => _isPrinting = true);
    PieSoundService.instance.click();
    try {
      await widget.onPrint();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: PieColors.surface2,
            content: Row(
              children: [
                Icon(Icons.check_circle_rounded, color: PieColors.stateSynced, size: 20),
                SizedBox(width: 8),
                Text('تم إرسال الفاتورة إلى أمر الطباعة بنجاح'),
              ],
            ),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isPrinting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final facility = widget.facility ?? const FacilitySettings();
    final ref = (order.canonicalOrderNumber?.isNotEmpty == true)
        ? order.canonicalOrderNumber!
        : (order.provisionalOrderNumber.isNotEmpty ? order.provisionalOrderNumber : order.localId);

    final title = facility.receiptName.isNotEmpty
        ? facility.receiptName
        : (facility.nameAr.isNotEmpty ? facility.nameAr : 'PIE Restaurant');

    final safeTotal = order.total.isFinite ? order.total : 0.0;
    final safeSubtotal = order.subtotal.isFinite ? order.subtotal : 0.0;
    final safeTax = order.taxAmount.isFinite ? order.taxAmount : 0.0;

    final dateStr =
        '${order.createdAt.year}-${order.createdAt.month.toString().padLeft(2, '0')}-${order.createdAt.day.toString().padLeft(2, '0')}';
    final timeStr =
        '${order.createdAt.hour.toString().padLeft(2, '0')}:${order.createdAt.minute.toString().padLeft(2, '0')}';

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        backgroundColor: PieColors.surfaceOverlay,
        shape: const RoundedRectangleBorder(
          borderRadius: PieRadius.borderLg,
          side: BorderSide(color: PieColors.border),
        ),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Container(
          width: 440,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.9,
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Top Success Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: PieColors.stateSyncedBg,
                            shape: BoxShape.circle,
                            border: Border.all(color: PieColors.stateSynced.withOpacity(0.3)),
                          ),
                          child: const Icon(
                            Icons.check_circle_rounded,
                            color: PieColors.stateSynced,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'تم إصدار الفاتورة',
                                style: PieTypography.subheading.copyWith(fontWeight: FontWeight.w700),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                'أوردر #$ref',
                                style: PieTypography.caption.copyWith(color: PieColors.cashierAccent),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
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
              const SizedBox(height: 14),

              // Visual Thermal Receipt Box
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: PieColors.surface1,
                    borderRadius: PieRadius.borderMd,
                    border: Border.all(color: PieColors.border),
                  ),
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Center(
                        child: Text(
                          title,
                          style: PieTypography.subheading.copyWith(fontWeight: FontWeight.w800),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      if (facility.activeBranchName.isNotEmpty)
                        Center(
                          child: Text(
                            'فرع: ${facility.activeBranchName}',
                            style: PieTypography.caption.copyWith(color: PieColors.inkSecondary),
                          ),
                        ),
                      if (facility.taxId.isNotEmpty)
                        Center(
                          child: Text(
                            'الرقم الضريبي: ${facility.taxId}',
                            style: PieTypography.caption.copyWith(color: PieColors.inkMuted),
                          ),
                        ),
                      const Divider(color: PieColors.border, height: 20),

                      // Meta
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              'نوع الطلب:',
                              style: PieTypography.caption,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          PieBadge.channel(order.orderType),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              'التاريخ والوقت:',
                              style: PieTypography.caption,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text('$dateStr • $timeStr', style: PieTypography.monoCaption),
                        ],
                      ),
                      const Divider(color: PieColors.border, height: 20),

                      // Items list
                      ...order.items.map((item) {
                        final lineTotal = item.unitPrice * item.quantity;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${item.quantity}× ',
                                    style: PieTypography.bodyStrong.copyWith(color: PieColors.cashierAccent),
                                  ),
                                  Expanded(
                                    child: Text(
                                      item.name,
                                      style: PieTypography.bodyStrong,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  PieNumeral.money(lineTotal, style: PieTypography.monoBody),
                                ],
                              ),
                              if (item.modifiers.isNotEmpty)
                                Text(
                                  item.modifiers.join(' • '),
                                  style: PieTypography.caption.copyWith(color: PieColors.cashierAccent),
                                ),
                              if (item.note != null && item.note!.isNotEmpty)
                                Text('ملاحظة: ${item.note}', style: PieTypography.caption),
                            ],
                          ),
                        );
                      }),

                      const Divider(color: PieColors.border, height: 20),

                      // Subtotal & Tax
                      _buildSummaryRow('المجموع الجزئي', safeSubtotal),
                      if (safeTax > 0) _buildSummaryRow('ضريبة القيمة المضافة', safeTax),
                      const Divider(color: PieColors.border, height: 16),

                      // Total
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              'الإجمالي النهائي',
                              style: PieTypography.subheading.copyWith(fontWeight: FontWeight.w700),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          PieNumeral.money(
                            safeTotal,
                            style: PieTypography.monoHeading.copyWith(
                              color: PieColors.cashierAccent,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Payment info
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              'طريقة الدفع:',
                              style: PieTypography.caption,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(widget.paymentMethod ?? 'نقدي', style: PieTypography.bodyStrong),
                        ],
                      ),
                      if (widget.paidAmount != null && widget.paidAmount! > 0) ...[
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                'المبلغ المستلم:',
                                style: PieTypography.caption,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            PieNumeral.money(widget.paidAmount!, style: PieTypography.monoCaption),
                          ],
                        ),
                      ],
                      if (widget.changeDue != null && widget.changeDue! > 0) ...[
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                'الباقي للعميل:',
                                style: PieTypography.bodyStrong.copyWith(color: PieColors.stateSynced),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            PieNumeral.money(
                              widget.changeDue!,
                              style: PieTypography.monoBody.copyWith(
                                color: PieColors.stateSynced,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Actions
              PieButton.primary(
                onPressed: _isPrinting ? null : _handlePrint,
                label: _isPrinting ? 'جاري الطباعة...' : 'طباعة الفاتورة الآن (بون)',
                icon: Icons.print_rounded,
                accentColor: PieColors.cashierAccent,
                isFullWidth: true,
                height: 50,
              ),
              if (widget.onOpenTab != null) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: widget.onOpenTab,
                    icon: const Icon(Icons.open_in_new_rounded, size: 16),
                    label: const Text('فتح الفاتورة في نافذة مستقلة للطباعة'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: PieColors.textPrimary,
                      side: const BorderSide(color: PieColors.border),
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      shape: const RoundedRectangleBorder(borderRadius: PieRadius.borderSm),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                  label: const Text('إنهاء ومتابعة البيع (أوردر جديد)'),
                  style: TextButton.styleFrom(
                    foregroundColor: PieColors.inkSecondary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String label, double amount) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: PieTypography.caption,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          PieNumeral.money(amount, style: PieTypography.monoCaption),
        ],
      ),
    );
  }
}

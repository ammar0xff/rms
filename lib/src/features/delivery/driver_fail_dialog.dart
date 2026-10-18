import 'package:flutter/material.dart';
import '../../core/di/app_services.dart';
import '../../core/theme/pie_colors.dart';
import '../../core/theme/pie_typography.dart';
import '../../core/widgets/pie_button.dart';
import '../../domain/models/delivery.dart';

/// Screen 11: Failed Delivery & Return Flow (تعذر التسليم ومرتجع الأوردر)
///
/// Functional contract:
/// - Mandatory failure reason selection (noAnswer, wrongAddress, refused, cashIssue, breakdown)
/// - Transition to failed state with reason recorded in local store & outbox
/// - Return leg initiation
class DriverFailDialog extends StatefulWidget {
  const DriverFailDialog({super.key, required this.delivery});

  final DeliveryModel delivery;

  static Future<bool?> show(BuildContext context, {required DeliveryModel delivery}) {
    return showDialog<bool>(
      context: context,
      builder: (context) => DriverFailDialog(delivery: delivery),
    );
  }

  @override
  State<DriverFailDialog> createState() => _DriverFailDialogState();
}

class _DriverFailDialogState extends State<DriverFailDialog> {
  DeliveryFailureReason _selectedReason = DeliveryFailureReason.noAnswer;

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        backgroundColor: PieColors.surfaceOverlay,
        child: Container(
          width: 400,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'تعذر تسليم الأوردر #${widget.delivery.orderRef}',
                      style: PieTypography.heading,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: PieColors.inkSecondary),
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'اختار سبب عدم اكتمال التوصيل لتسجيله في الدفتر وإرجاع الأوردر للفرع:',
                style: PieTypography.body,
              ),
              const SizedBox(height: 16),
              for (final reason in DeliveryFailureReason.values) ...[
                RadioListTile<DeliveryFailureReason>(
                  value: reason,
                  groupValue: _selectedReason,
                  title: Text(reason.label, style: PieTypography.bodyStrong),
                  activeColor: PieColors.stateError,
                  fillColor: MaterialStateProperty.all(
                    _selectedReason == reason ? PieColors.stateError : PieColors.inkSecondary,
                  ),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedReason = val);
                  },
                ),
              ],
              const SizedBox(height: 20),
              PieButton.destructive(
                onPressed: () async {
                  await services.deliveries?.failDelivery(
                    widget.delivery.id,
                    _selectedReason,
                  );
                  if (mounted) {
                    Navigator.of(context).pop(true);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        backgroundColor: PieColors.surface2,
                        content: Text(
                          'تم تسجيل تعذر التسليم (${_selectedReason.label}) وبدء خط العودة للفرع',
                          style: PieTypography.body.copyWith(color: PieColors.stateError),
                        ),
                      ),
                    );
                  }
                },
                label: 'تأكيد تعذر التسليم وبدء الرجوع',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

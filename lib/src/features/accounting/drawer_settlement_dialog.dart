import 'package:flutter/material.dart';
import '../../core/di/app_services.dart';
import '../../core/theme/pie_colors.dart';
import '../../core/theme/pie_typography.dart';
import '../../core/widgets/pie_button.dart';
import '../../domain/models/audit_entry.dart';

/// Screen 7: Drawer Settlement Dialog (تسوية العهدة وتوريد الكاش للخزينة)
class DrawerSettlementDialog extends StatefulWidget {
  const DrawerSettlementDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (context) => const DrawerSettlementDialog(),
    );
  }

  @override
  State<DrawerSettlementDialog> createState() => _DrawerSettlementDialogState();
}

class _DrawerSettlementDialogState extends State<DrawerSettlementDialog> {
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();
  String _settlementType = 'توريد للخزينة الرئيسية';

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        backgroundColor: PieColors.surfaceOverlay,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Container(
          width: 420,
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'تسوية الدرج وتوريد النقدية',
                        style: PieTypography.heading,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: PieColors.inkSecondary),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              Text(
                'نوع التوريد:',
                style: PieTypography.label,
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: _settlementType,
                dropdownColor: PieColors.surface2,
                items: [
                  'توريد للخزينة الرئيسية',
                  'تسوية نثريات ومصروفات',
                  'إيداع بنكي وسيط',
                ].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _settlementType = val);
                },
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _amountController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'المبلغ المورّد (ج.م)',
                  hintText: '0.00',
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _noteController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'ملاحظات أو رقم الإيصال',
                  hintText: 'رقم إيصال التوريد أو سبب الصرف...',
                ),
              ),
              const SizedBox(height: 24),
              PieButton.primary(
                onPressed: () async {
                  final amount = double.tryParse(_amountController.text) ?? 0.0;
                  if (amount <= 0) return;

                  // Record settlement via audit/cash repo
                  services.audit?.record(
                    AuditEntry(
                      id: 'settlement_${DateTime.now().millisecondsSinceEpoch}',
                      action: AuditAction.closeCashSession,
                      entityType: 'drawer_settlement',
                      entityId: 'settlement_${DateTime.now().millisecondsSinceEpoch}',
                      summary: 'تسوية درج: $_settlementType بمبلغ $amount (${_noteController.text.trim()})',
                      amount: amount,
                      at: DateTime.now(),
                      actor: 'cashier',
                      createdOffline: services.sync?.isOnline != true,
                    ),
                  );

                  if (mounted) {
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        backgroundColor: PieColors.surface2,
                        content: Text('تم تسجيل تسوية الدرج بنجاح'),
                      ),
                    );
                  }
                },
                label: 'تأكيد التسوية والتوريد',
                accentColor: PieColors.cashierAccent,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

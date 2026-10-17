import 'package:flutter/material.dart';
import '../../core/theme/pie_colors.dart';
import '../../core/theme/pie_typography.dart';
import '../../core/widgets/pie_button.dart';
import '../../core/widgets/pie_numeral.dart';
import '../../domain/models/payment.dart';

/// Checkout & Tender Dialog (الدفع وإنهاء الفاتورة)
///
/// Functional contract:
/// - Exact bill breakdown: Subtotal, discount, service, tax, Total
/// - Numeric keypad for entering cash tendered
/// - Quick-tender chips (+50, +100, +200, exact)
/// - Cash vs Card toggle (كاش / فيزا)
/// - Change due calculation in real-time
class PosCheckoutDialog extends StatefulWidget {
  const PosCheckoutDialog({
    super.key,
    required this.totalAmount,
    required this.subtotal,
    required this.taxAmount,
    required this.serviceAmount,
    required this.discountAmount,
    required this.onComplete,
  });

  final double totalAmount;
  final double subtotal;
  final double taxAmount;
  final double serviceAmount;
  final double discountAmount;
  final ValueChanged<PaymentMethod> onComplete;

  static Future<bool?> show(
    BuildContext context, {
    required double totalAmount,
    required double subtotal,
    required double taxAmount,
    required double serviceAmount,
    required double discountAmount,
    required ValueChanged<PaymentMethod> onComplete,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PosCheckoutDialog(
        totalAmount: totalAmount,
        subtotal: subtotal,
        taxAmount: taxAmount,
        serviceAmount: serviceAmount,
        discountAmount: discountAmount,
        onComplete: onComplete,
      ),
    );
  }

  @override
  State<PosCheckoutDialog> createState() => _PosCheckoutDialogState();
}

class _PosCheckoutDialogState extends State<PosCheckoutDialog> {
  PaymentMethod _selectedMethod = PaymentMethod.cash;
  String _tenderedInput = '';

  double get _tenderedAmount {
    if (_tenderedInput.isEmpty) return 0.0;
    return double.tryParse(_tenderedInput) ?? 0.0;
  }

  double get _changeDue {
    if (_selectedMethod != PaymentMethod.cash) return 0.0;
    final diff = _tenderedAmount - widget.totalAmount;
    return diff > 0 ? diff : 0.0;
  }

  bool get _canSettle {
    if (_selectedMethod == PaymentMethod.card) return true;
    return _tenderedAmount >= widget.totalAmount;
  }

  void _onKeypadTap(String key) {
    setState(() {
      if (key == 'C') {
        _tenderedInput = '';
      } else if (key == '00') {
        if (_tenderedInput.isNotEmpty) _tenderedInput += '00';
      } else {
        _tenderedInput += key;
      }
    });
  }

  void _onQuickChipTap(double amount) {
    setState(() {
      _tenderedInput = amount.toStringAsFixed(0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = screenWidth < 600;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        backgroundColor: PieColors.surfaceOverlay,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Container(
          width: 580,
          constraints: const BoxConstraints(maxHeight: 700),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'الدفع وإنهاء الفاتورة',
                    style: PieTypography.heading.copyWith(fontWeight: FontWeight.w700),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: PieColors.inkSecondary),
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Payment Method Toggle (Cash vs Card)
              Row(
                children: [
                  Expanded(
                    child: _buildMethodButton(
                      method: PaymentMethod.cash,
                      title: 'كاش (نقدي)',
                      icon: Icons.payments_outlined,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildMethodButton(
                      method: PaymentMethod.card,
                      title: 'فيزا (بطاقة)',
                      icon: Icons.credit_card_rounded,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Breakdown & Keypad
              Expanded(
                child: isCompact ? _buildCompactBody() : _buildWideBody(),
              ),

              const SizedBox(height: 20),

              // Settle Action
              PieButton.primary(
                onPressed: _canSettle
                    ? () {
                        widget.onComplete(_selectedMethod);
                        Navigator.of(context).pop(true);
                      }
                    : null,
                label: _selectedMethod == PaymentMethod.cash && _changeDue > 0
                    ? 'إنهاء الدفع • الباقي: ${PieTypography.formatEgp(_changeDue)}'
                    : 'إنهاء الدفع وطباعة الفاتورة • ${PieTypography.formatEgp(widget.totalAmount)}',
                accentColor: PieColors.cashierAccent,
                height: 52,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMethodButton({
    required PaymentMethod method,
    required String title,
    required IconData icon,
  }) {
    final isSelected = _selectedMethod == method;

    return Material(
      color: isSelected ? PieColors.cashierSurface : PieColors.surface2,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedMethod = method;
            if (method == PaymentMethod.cash && _tenderedInput.isEmpty) {
              _tenderedInput = widget.totalAmount.toStringAsFixed(0);
            }
          });
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? PieColors.cashierAccent : PieColors.border,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 20,
                color: isSelected ? PieColors.cashierAccent : PieColors.inkSecondary,
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: PieTypography.bodyStrong.copyWith(
                  color: isSelected ? PieColors.cashierAccent : PieColors.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWideBody() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left Column: Bill Breakdown & Tender calculation
        Expanded(
          flex: 5,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildBillBreakdownCard(),
              if (_selectedMethod == PaymentMethod.cash) ...[
                const SizedBox(height: 16),
                _buildCashTenderCard(),
              ],
            ],
          ),
        ),
        if (_selectedMethod == PaymentMethod.cash) ...[
          const SizedBox(width: 16),
          // Right Column: Keypad & Quick chips
          Expanded(
            flex: 5,
            child: _buildKeypadSection(),
          ),
        ],
      ],
    );
  }

  Widget _buildCompactBody() {
    return ListView(
      children: [
        _buildBillBreakdownCard(),
        if (_selectedMethod == PaymentMethod.cash) ...[
          const SizedBox(height: 16),
          _buildCashTenderCard(),
          const SizedBox(height: 16),
          _buildKeypadSection(),
        ],
      ],
    );
  }

  Widget _buildBillBreakdownCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PieColors.surface1,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: PieColors.border),
      ),
      child: Column(
        children: [
          _buildBreakdownRow('المجموع الجزئي', widget.subtotal),
          if (widget.discountAmount > 0)
            _buildBreakdownRow('الخصم', -widget.discountAmount, isNegative: true),
          if (widget.serviceAmount > 0)
            _buildBreakdownRow('خدمة الصالة', widget.serviceAmount),
          if (widget.taxAmount > 0)
            _buildBreakdownRow('ضريبة القيمة المضافة', widget.taxAmount),
          const Divider(color: PieColors.border, height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'الإجمالي المطلوب',
                style: PieTypography.subheading.copyWith(fontWeight: FontWeight.w700),
              ),
              PieNumeral.money(
                widget.totalAmount,
                style: PieTypography.monoHeading.copyWith(
                  color: PieColors.cashierAccent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCashTenderCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PieColors.surface2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: PieColors.border),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('المبلغ المدفوع:', style: PieTypography.body),
              PieNumeral.money(
                _tenderedAmount,
                style: PieTypography.monoHeading.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'الباقي للعميل:',
                style: PieTypography.bodyStrong.copyWith(
                  color: _changeDue > 0 ? PieColors.cashierAccent : PieColors.inkSecondary,
                ),
              ),
              PieNumeral.money(
                _changeDue,
                style: PieTypography.monoHeading.copyWith(
                  color: _changeDue > 0 ? PieColors.cashierAccent : PieColors.inkSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKeypadSection() {
    final next50 = (widget.totalAmount / 50).ceil() * 50.0;
    final next100 = (widget.totalAmount / 100).ceil() * 100.0;
    final next200 = (widget.totalAmount / 200).ceil() * 200.0;

    return Column(
      children: [
        // Quick tender chips
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            ActionChip(
              label: const Text('بالضبط'),
              backgroundColor: PieColors.surface2,
              side: const BorderSide(color: PieColors.border),
              labelStyle: PieTypography.caption.copyWith(color: PieColors.cashierAccent),
              onPressed: () => _onQuickChipTap(widget.totalAmount),
            ),
            if (next50 != widget.totalAmount)
              ActionChip(
                label: Text('${next50.toInt()} ج.م'),
                backgroundColor: PieColors.surface2,
                side: const BorderSide(color: PieColors.border),
                labelStyle: PieTypography.caption,
                onPressed: () => _onQuickChipTap(next50),
              ),
            if (next100 != next50 && next100 != widget.totalAmount)
              ActionChip(
                label: Text('${next100.toInt()} ج.م'),
                backgroundColor: PieColors.surface2,
                side: const BorderSide(color: PieColors.border),
                labelStyle: PieTypography.caption,
                onPressed: () => _onQuickChipTap(next100),
              ),
            if (next200 != next100 && next200 != widget.totalAmount)
              ActionChip(
                label: Text('${next200.toInt()} ج.م'),
                backgroundColor: PieColors.surface2,
                side: const BorderSide(color: PieColors.border),
                labelStyle: PieTypography.caption,
                onPressed: () => _onQuickChipTap(next200),
              ),
          ],
        ),
        const SizedBox(height: 12),
        // Keypad grid
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollifPossible(),
          crossAxisCount: 3,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 1.8,
          children: [
            for (final k in ['1', '2', '3', '4', '5', '6', '7', '8', '9', '00', '0', 'C'])
              Material(
                color: k == 'C' ? PieColors.stateErrorBg : PieColors.surface2,
                borderRadius: BorderRadius.circular(6),
                child: InkWell(
                  onTap: () => _onKeypadTap(k),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: k == 'C' ? PieColors.stateError.withOpacity(0.5) : PieColors.border,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      k,
                      style: PieTypography.monoHeading.copyWith(
                        color: k == 'C' ? PieColors.stateError : PieColors.ink,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildBreakdownRow(String title, double amount, {bool isNegative = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: PieTypography.body),
          PieNumeral.money(
            amount.abs(),
            prefix: isNegative ? '- ' : null,
            style: PieTypography.monoBody.copyWith(
              color: isNegative ? PieColors.stateError : PieColors.inkSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class NeverScrollableScrollifPossible extends ScrollPhysics {
  const NeverScrollableScrollifPossible({super.parent});

  @override
  NeverScrollableScrollifPossible applyTo(ScrollPhysics? ancestor) {
    return NeverScrollableScrollifPossible(parent: buildParent(ancestor));
  }

  @override
  bool shouldAcceptUserOffset(ScrollMetrics position) => false;
}

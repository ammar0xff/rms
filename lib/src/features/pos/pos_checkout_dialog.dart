import 'package:flutter/material.dart';
import '../../core/di/app_services.dart';
import '../../core/sound/pie_sound_service.dart';
import '../../core/theme/pie_colors.dart';
import '../../core/theme/pie_radius.dart';
import '../../core/theme/pie_typography.dart';
import '../../core/widgets/pie_button.dart';
import '../../core/widgets/pie_numeral.dart';
import '../../core/widgets/pie_toast.dart';
import '../../domain/models/delivery_zone.dart';
import '../../domain/models/order_type.dart';
import '../../domain/models/payment.dart';

typedef PosCheckoutCallback = Future<void> Function(
  PaymentMethod paymentMethod, {
  String? customerName,
  String? customerPhone,
  String? deliveryAddress,
  double? tenderedAmount,
  String? zoneName,
  double? zoneFee,
});

/// Checkout & Tender Dialog (الدفع وإنهاء الفاتورة)
///
/// Features:
/// - Customer information validation (mandatory for delivery, optional for takeaway)
/// - Exact bill breakdown: Subtotal, discount, service, tax, Total
/// - Numeric keypad for entering cash tendered
/// - Quick-tender chips (+50, +100, +200, exact)
/// - Cash vs Card toggle (كاش / فيزا)
/// - Change due calculation in real-time
/// - Sound effects & tactile audio feedback
class PosCheckoutDialog extends StatefulWidget {
  const PosCheckoutDialog({
    super.key,
    required this.totalAmount,
    required this.subtotal,
    required this.taxAmount,
    required this.serviceAmount,
    required this.discountAmount,
    required this.onComplete,
    this.orderType = OrderType.takeaway,
  });

  final double totalAmount;
  final double subtotal;
  final double taxAmount;
  final double serviceAmount;
  final double discountAmount;
  final OrderType orderType;
  final PosCheckoutCallback onComplete;

  static Future<bool?> show(
    BuildContext context, {
    required double totalAmount,
    required double subtotal,
    required double taxAmount,
    required double serviceAmount,
    required double discountAmount,
    required OrderType orderType,
    required PosCheckoutCallback onComplete,
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
        orderType: orderType,
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

  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _addressController;

  List<DeliveryZone> _availableZones = [];
  DeliveryZone? _selectedZone;
  bool _loadingZones = false;

  bool _attemptedSettle = false;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _phoneController = TextEditingController();
    _addressController = TextEditingController();
    if (_isDelivery) {
      _loadingZones = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadDeliveryZones());
    } else {
      _tenderedInput = widget.totalAmount.toStringAsFixed(0);
    }
  }

  Future<void> _loadDeliveryZones() async {
    final services = AppScope.of(context);
    final zones = await services.deliveries?.listZones() ?? [];
    if (mounted) {
      final activeZones = zones.where((z) => z.active).toList();
      setState(() {
        _availableZones = activeZones;
        _loadingZones = false;
        if (activeZones.isNotEmpty) {
          _selectedZone = activeZones.first;
        }
        _tenderedInput = _effectiveTotal.toStringAsFixed(0);
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  bool get _isDelivery => widget.orderType == OrderType.delivery;

  double get _deliveryFee => _isDelivery ? (_selectedZone?.fee ?? 0.0) : 0.0;
  double get _effectiveTotal => widget.totalAmount + _deliveryFee;

  bool get _isNameValid {
    if (!_isDelivery) return true;
    return _nameController.text.trim().isNotEmpty;
  }

  bool get _isPhoneValid {
    final phone = _phoneController.text.trim();
    if (!_isDelivery && phone.isEmpty) return true;
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    return digits.length >= 8;
  }

  bool get _isAddressValid {
    if (!_isDelivery) return true;
    return _addressController.text.trim().isNotEmpty;
  }

  bool get _isCustomerValid {
    if (!_isDelivery) return true;
    final hasZone = _availableZones.isEmpty || _selectedZone != null;
    return _isNameValid && _isPhoneValid && _isAddressValid && hasZone;
  }

  double get _tenderedAmount {
    if (_tenderedInput.isEmpty) return _effectiveTotal;
    return double.tryParse(_tenderedInput) ?? _effectiveTotal;
  }

  double get _changeDue {
    if (_selectedMethod != PaymentMethod.cash) return 0.0;
    final diff = _tenderedAmount - _effectiveTotal;
    return diff > 0 ? diff : 0.0;
  }

  bool get _canSettle {
    if (!_isCustomerValid) return false;
    if (_selectedMethod == PaymentMethod.card) return true;
    if (_isDelivery && _selectedMethod == PaymentMethod.cash) return true;
    return _tenderedAmount >= _effectiveTotal;
  }

  void _onKeypadTap(String key) {
    PieSoundService.instance.click();
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
    PieSoundService.instance.click();
    setState(() {
      _tenderedInput = amount.toStringAsFixed(0);
    });
  }

  Future<void> _handleSettle() async {
    setState(() => _attemptedSettle = true);

    if (!_isCustomerValid) {
      PieSoundService.instance.beep();
      PieToast.show(
        context,
        _isDelivery
            ? (_selectedZone == null && _availableZones.isNotEmpty
                ? 'يرجى اختيار منطقة التوصيل المعتمدة لحساب الرسوم'
                : 'يرجى إدخال اسم العميل ورقم الهاتف وعنوان التوصيل بدقة')
            : 'بيانات غير مكتملة',
        isError: true,
      );
      return;
    }

    if (!_canSettle) {
      PieSoundService.instance.beep();
      PieToast.show(
        context,
        'المبلغ المستلم (${PieTypography.formatEgp(_tenderedAmount)}) أقل من إجمالي الفاتورة (${PieTypography.formatEgp(_effectiveTotal)})',
        isError: true,
      );
      return;
    }

    setState(() => _isSubmitting = true);
    PieSoundService.instance.chime();

    try {
      final cashRepo = AppScope.of(context).cashSessions;
      if (cashRepo != null) {
        final currentSession = await cashRepo.currentSession();
        if (currentSession == null || !currentSession.isOpen) {
          PieSoundService.instance.beep();
          if (mounted) {
            PieToast.show(
              context,
              'لا يمكن إتمام الدفع: الوردية الحالية مغلقة. يرجى فتح وردية أولاً.',
              isError: true,
            );
          }
          return;
        }
      }

      await widget.onComplete(
        _selectedMethod,
        customerName: _nameController.text.trim().isEmpty ? null : _nameController.text.trim(),
        customerPhone: _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
        deliveryAddress: _isDelivery ? _addressController.text.trim() : null,
        tenderedAmount: (_isDelivery && _selectedMethod == PaymentMethod.cash)
            ? _effectiveTotal
            : _tenderedAmount,
        zoneName: _selectedZone?.name,
        zoneFee: _deliveryFee,
      );
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        PieToast.show(
          context,
          'تعذر إتمام الدفع: $e',
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = screenWidth < 700;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        backgroundColor: PieColors.surfaceOverlay,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Container(
          width: isCompact ? double.infinity : 660,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.9,
          ),
          padding: EdgeInsets.all(isCompact ? 16 : 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: PieColors.cashierSurface,
                            borderRadius: PieRadius.borderMd,
                          ),
                          child: Icon(
                            _isDelivery ? Icons.two_wheeler_rounded : Icons.shopping_bag_outlined,
                            color: PieColors.cashierAccent,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _isDelivery ? 'دفع وإنهاء طلب الدليفري' : 'الدفع وإنهاء الفاتورة (تيك أواي)',
                            style: (isCompact ? PieTypography.subheading : PieTypography.heading)
                                .copyWith(fontWeight: FontWeight.w700),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: PieColors.inkSecondary),
                    onPressed: () {
                      PieSoundService.instance.click();
                      Navigator.of(context).pop(false);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 14),

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
              const SizedBox(height: 14),

              // Breakdown, Customer inputs & Keypad
              Expanded(
                child: isCompact ? _buildCompactBody() : _buildWideBody(),
              ),

              const SizedBox(height: 14),

              // Settle Action
              PieButton.primary(
                onPressed: _isSubmitting ? null : _handleSettle,
                label: _isSubmitting
                    ? 'جاري حفظ الطلب...'
                    : (_isDelivery && _selectedMethod == PaymentMethod.cash)
                        ? 'تأكيد وحفظ أوردر الدليفري • ${PieTypography.formatEgp(_effectiveTotal)}'
                        : _selectedMethod == PaymentMethod.cash && _changeDue > 0
                            ? 'إنهاء الدفع • الباقي: ${PieTypography.formatEgp(_changeDue)}'
                            : 'إنهاء الدفع وحفظ الطلب • ${PieTypography.formatEgp(_effectiveTotal)}',
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
      borderRadius: PieRadius.borderMd,
      child: InkWell(
        onTap: () {
          PieSoundService.instance.click();
          setState(() {
            _selectedMethod = method;
            if (method == PaymentMethod.cash && _tenderedInput.isEmpty) {
              _tenderedInput = _effectiveTotal.toStringAsFixed(0);
            }
          });
        },
        borderRadius: PieRadius.borderMd,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            borderRadius: PieRadius.borderMd,
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

  Widget _buildCustomerSection() {
    final showErrorName = _attemptedSettle && !_isNameValid;
    final showErrorPhone = _attemptedSettle && !_isPhoneValid;
    final showErrorAddress = _attemptedSettle && !_isAddressValid;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: PieColors.surface1,
        borderRadius: PieRadius.borderMd,
        border: Border.all(
          color: (_attemptedSettle && !_isCustomerValid)
              ? PieColors.stateError.withOpacity(0.6)
              : PieColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                _isDelivery ? Icons.local_shipping_outlined : Icons.person_outline,
                size: 16,
                color: _isDelivery ? PieColors.driverAccent : PieColors.inkSecondary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _isDelivery ? 'بيانات العميل والتوصيل (إلزامية)' : 'بيانات العميل (اختيارية)',
                  style: PieTypography.label.copyWith(
                    fontWeight: FontWeight.w700,
                    color: _isDelivery ? PieColors.ink : PieColors.inkSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_isDelivery) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: PieColors.stateErrorBg,
                    borderRadius: PieRadius.borderSm,
                  ),
                  child: Text(
                    'مطلوب',
                    style: PieTypography.caption.copyWith(
                      color: PieColors.stateError,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildTextField(
                  controller: _nameController,
                  label: 'اسم العميل',
                  hint: 'أحمد محمود',
                  isError: showErrorName,
                  isRequired: _isDelivery,
                  icon: Icons.badge_outlined,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildTextField(
                  controller: _phoneController,
                  label: 'رقم الهاتف',
                  hint: '01xxxxxxxxx',
                  isError: showErrorPhone,
                  isRequired: _isDelivery,
                  keyboardType: TextInputType.phone,
                  icon: Icons.phone_outlined,
                ),
              ),
            ],
          ),
          if (_isDelivery) ...[
            const SizedBox(height: 8),
            _buildZoneSelector(),
            const SizedBox(height: 8),
            _buildTextField(
              controller: _addressController,
              label: 'عنوان التوصيل بالتفصيل',
              hint: 'الشارع، رقم العمارة، رقم الشقة / الدور',
              isError: showErrorAddress,
              isRequired: true,
              icon: Icons.location_on_outlined,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildZoneSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                'منطقة ورسوم التوصيل (محددة من الإدارة)',
                style: PieTypography.caption.copyWith(
                  fontWeight: FontWeight.w600,
                  color: PieColors.inkSecondary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (_selectedZone != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: PieColors.driverSurface,
                  borderRadius: PieRadius.borderSm,
                  border: Border.all(color: PieColors.driverBorder),
                ),
                child: Text(
                  '${_selectedZone!.fee.toStringAsFixed(0)} ج.م (ثابت)',
                  style: PieTypography.monoCaption.copyWith(
                    color: PieColors.driverAccent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: PieColors.surface2,
            borderRadius: PieRadius.borderMd,
            border: Border.all(
              color: (_attemptedSettle && _selectedZone == null && _availableZones.isNotEmpty)
                  ? PieColors.stateError
                  : PieColors.border,
            ),
          ),
          child: _loadingZones
              ? const Center(
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: PieColors.cashierAccent),
                  ),
                )
              : _availableZones.isEmpty
                  ? Row(
                      children: [
                        const Icon(Icons.info_outline_rounded, size: 16, color: PieColors.inkMuted),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'لا توجد مناطق توصيل معرفة. (رسوم التوصيل: 0 ج.م)',
                            style: PieTypography.caption.copyWith(color: PieColors.inkMuted),
                          ),
                        ),
                      ],
                    )
                  : DropdownButtonHideUnderline(
                      child: DropdownButton<DeliveryZone>(
                        isExpanded: true,
                        value: _selectedZone,
                        dropdownColor: PieColors.surfaceOverlay,
                        icon: const Icon(Icons.keyboard_arrow_down_rounded, color: PieColors.inkSecondary),
                        items: _availableZones.map((zone) {
                          return DropdownMenuItem<DeliveryZone>(
                            value: zone,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.location_on_outlined, size: 16, color: PieColors.driverAccent),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          zone.name,
                                          style: PieTypography.body,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: PieColors.surface3,
                                    borderRadius: PieRadius.borderSm,
                                  ),
                                  child: Text(
                                    '${zone.fee.toStringAsFixed(0)} ج.م',
                                    style: PieTypography.caption.copyWith(
                                      color: PieColors.cashierAccent,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                        onChanged: (newZone) {
                          if (newZone != null) {
                            PieSoundService.instance.click();
                            setState(() {
                              _selectedZone = newZone;
                              if (_selectedMethod == PaymentMethod.cash) {
                                _tenderedInput = _effectiveTotal.toStringAsFixed(0);
                              }
                            });
                          }
                        },
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required bool isError,
    required bool isRequired,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                label,
                style: PieTypography.caption.copyWith(
                  color: isError ? PieColors.stateError : PieColors.inkSecondary,
                  fontWeight: isRequired ? FontWeight.w600 : FontWeight.w400,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isError) ...[
              const SizedBox(width: 4),
              Text(
                'مطلوب',
                style: PieTypography.caption.copyWith(color: PieColors.stateError, fontSize: 10),
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Container(
          height: 38,
          decoration: BoxDecoration(
            color: PieColors.surface2,
            borderRadius: PieRadius.borderMd,
            border: Border.all(
              color: isError ? PieColors.stateError : PieColors.border,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              Icon(icon, size: 16, color: isError ? PieColors.stateError : PieColors.inkMuted),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  controller: controller,
                  keyboardType: keyboardType,
                  onChanged: (_) {
                    if (_attemptedSettle) setState(() {});
                  },
                  style: PieTypography.body.copyWith(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: hint,
                    hintStyle: PieTypography.body.copyWith(
                      color: PieColors.inkMuted,
                      fontSize: 12,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWideBody() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left Column: Customer details & Bill Breakdown
        Expanded(
          flex: 5,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildCustomerSection(),
                const SizedBox(height: 12),
                _buildBillBreakdownCard(),
                if (_selectedMethod == PaymentMethod.cash && !_isDelivery) ...[
                  const SizedBox(height: 12),
                  _buildCashTenderCard(),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(width: 14),
        // Right Column: Keypad & Quick chips OR Delivery COD Card OR Card Terminal Card
        Expanded(
          flex: 5,
          child: _selectedMethod == PaymentMethod.cash
              ? (_isDelivery
                  ? Center(child: _buildDeliveryCodCard())
                  : SingleChildScrollView(child: _buildKeypadSection()))
              : Center(child: _buildCardTerminalCard()),
        ),
      ],
    );
  }

  Widget _buildCompactBody() {
    return ListView(
      children: [
        _buildCustomerSection(),
        const SizedBox(height: 12),
        _buildBillBreakdownCard(),
        if (_selectedMethod == PaymentMethod.cash) ...[
          const SizedBox(height: 12),
          if (_isDelivery)
            _buildDeliveryCodCard()
          else ...[
            _buildCashTenderCard(),
            const SizedBox(height: 12),
            _buildKeypadSection(),
          ],
        ] else ...[
          const SizedBox(height: 12),
          _buildCardTerminalCard(),
        ],
      ],
    );
  }

  Widget _buildDeliveryCodCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: PieColors.surface1,
        borderRadius: PieRadius.borderMd,
        border: Border.all(color: PieColors.driverBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              color: PieColors.driverSurface,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.two_wheeler_rounded, size: 40, color: PieColors.driverAccent),
          ),
          const SizedBox(height: 12),
          Text(
            'تحصيل كاش عند الاستلام (COD)',
            style: PieTypography.bodyStrong.copyWith(color: PieColors.ink),
          ),
          const SizedBox(height: 8),
          Text(
            'المبلغ المطلوب تحصيله من العميل بواسطة الطيار:\n${PieTypography.formatEgp(_effectiveTotal)}',
            style: PieTypography.subheading.copyWith(
              color: PieColors.cashierAccent,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: PieColors.surface2,
              borderRadius: PieRadius.borderSm,
              border: Border.all(color: PieColors.border),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline_rounded, size: 16, color: PieColors.driverAccent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'أموال طلبات الدليفري الكاش لا تدخل درج الكاشير الآن، بل تُسجل كعهدة مالية في ذمة الطيار ويتم توريدها لاحقاً في شاشة إدارة الأسطول.',
                    style: PieTypography.caption.copyWith(color: PieColors.inkSecondary),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardTerminalCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: PieColors.surface1,
        borderRadius: PieRadius.borderMd,
        border: Border.all(color: PieColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle_outline, size: 48, color: PieColors.cashierAccent),
          const SizedBox(height: 12),
          Text(
            'جاهز لخصم البطاقة (POS Terminal)',
            style: PieTypography.bodyStrong,
          ),
          const SizedBox(height: 6),
          Text(
            'مرر البطاقة على نقطة البيع ثم اضغط إنهاء الدفع',
            style: PieTypography.caption,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildBillBreakdownCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: PieColors.surface1,
        borderRadius: PieRadius.borderMd,
        border: Border.all(color: PieColors.border),
      ),
      child: Column(
        children: [
          _buildBreakdownRow('المجموع الجزئي', widget.subtotal),
          if (widget.discountAmount > 0)
            _buildBreakdownRow('الخصم', -widget.discountAmount, isNegative: true),
          if (widget.taxAmount > 0)
            _buildBreakdownRow('ضريبة القيمة المضافة', widget.taxAmount),
          if (widget.serviceAmount > 0)
            _buildBreakdownRow('خدمة الصالة', widget.serviceAmount),
          if (_isDelivery && _selectedZone != null)
            _buildBreakdownRow('خدمة التوصيل (${_selectedZone!.name})', _deliveryFee),
          const Divider(color: PieColors.border, height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'الإجمالي المطلوب',
                  style: PieTypography.subheading.copyWith(fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              PieNumeral.money(
                _effectiveTotal,
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: PieColors.surface2,
        borderRadius: PieRadius.borderMd,
        border: Border.all(color: PieColors.border),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'المبلغ المدفوع:',
                  style: PieTypography.body,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              PieNumeral.money(
                _tenderedAmount,
                style: PieTypography.monoHeading.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'الباقي للعميل:',
                  style: PieTypography.bodyStrong.copyWith(
                    color: _changeDue > 0 ? PieColors.cashierAccent : PieColors.inkSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
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
    final next50 = (_effectiveTotal / 50).ceil() * 50.0;
    final next100 = (_effectiveTotal / 100).ceil() * 100.0;
    final next200 = (_effectiveTotal / 200).ceil() * 200.0;

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
              onPressed: () => _onQuickChipTap(_effectiveTotal),
            ),
            if (next50 != _effectiveTotal)
              ActionChip(
                label: Text('${next50.toInt()} ج.م'),
                backgroundColor: PieColors.surface2,
                side: const BorderSide(color: PieColors.border),
                labelStyle: PieTypography.caption,
                onPressed: () => _onQuickChipTap(next50),
              ),
            if (next100 != next50 && next100 != _effectiveTotal)
              ActionChip(
                label: Text('${next100.toInt()} ج.م'),
                backgroundColor: PieColors.surface2,
                side: const BorderSide(color: PieColors.border),
                labelStyle: PieTypography.caption,
                onPressed: () => _onQuickChipTap(next100),
              ),
            if (next200 != next100 && next200 != _effectiveTotal)
              ActionChip(
                label: Text('${next200.toInt()} ج.م'),
                backgroundColor: PieColors.surface2,
                side: const BorderSide(color: PieColors.border),
                labelStyle: PieTypography.caption,
                onPressed: () => _onQuickChipTap(next200),
              ),
          ],
        ),
        const SizedBox(height: 10),
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
                borderRadius: PieRadius.borderMd,
                child: InkWell(
                  onTap: () => _onKeypadTap(k),
                  borderRadius: PieRadius.borderMd,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: PieRadius.borderMd,
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
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              title,
              style: PieTypography.body,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
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

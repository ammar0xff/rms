import 'package:flutter/material.dart';
import '../../core/theme/pie_colors.dart';
import '../../core/theme/pie_radius.dart';
import '../../core/theme/pie_typography.dart';
import '../../core/widgets/pie_button.dart';
import '../../data/services/pin_service.dart';

/// Screen 18: PIN Gate & Delegation (تأكيد كود المدير وتفويض العمليات)
///
/// Functional contract:
/// - 4-digit PIN verification keypad
/// - Temporary supervisor delegation code generation
class PinDelegationDialog extends StatefulWidget {
  const PinDelegationDialog({
    super.key,
    required this.title,
    this.allowDelegation = false,
  });

  final String title;
  final bool allowDelegation;

  /// Asks for the manager PIN and verifies it against the stored salted hash.
  ///
  /// The comparison happens in [PinService] — never in this widget, and never
  /// against a literal. A PIN compiled into the app is a PIN every operator
  /// can read out of the binary, which would make this gate theatre.
  static Future<bool> verify(
    BuildContext context, {
    String title = 'تأكيد كود المدير',
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PinDelegationDialog(title: title),
    );
    return result == true;
  }

  @override
  State<PinDelegationDialog> createState() => _PinDelegationDialogState();
}

class _PinDelegationDialogState extends State<PinDelegationDialog> {
  String _enteredPin = '';
  String? _error;
  bool _showingDelegation = false;
  final String _generatedDelegationCode = 'DEL-7921';

  void _onDigit(String digit) {
    if (_enteredPin.length < 4) {
      setState(() {
        _error = null;
        _enteredPin += digit;
      });

      if (_enteredPin.length == 4) {
        _verifyPin();
      }
    }
  }

  void _onBackspace() {
    if (_enteredPin.isNotEmpty) {
      setState(() {
        _error = null;
        _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
      });
    }
  }

  Future<void> _verifyPin() async {
    // Verify against the stored hash. A wrong PIN, an unset PIN and an
    // unreachable backend all read the same way to the operator: refused.
    final ok = await PinService().verify(_enteredPin);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _error = 'كود المدير غير صحيح. حاول مرة ثانية.';
        _enteredPin = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        backgroundColor: PieColors.surfaceOverlay,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Container(
          width: 340,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
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
              const SizedBox(height: 8),
              Text(
                'العملية دي محتاجة اعتماد المدير المسؤول.',
                style: PieTypography.caption.copyWith(color: PieColors.inkSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),

              if (_showingDelegation) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: PieColors.surface2,
                    borderRadius: PieRadius.borderMd,
                    border: Border.all(color: PieColors.border),
                  ),
                  child: Column(
                    children: [
                      Text('كود التفويض المؤقت (صالح لساعة واحدة):', style: PieTypography.caption),
                      const SizedBox(height: 8),
                      Text(
                        _generatedDelegationCode,
                        style: PieTypography.monoDisplay.copyWith(color: PieColors.managerAccent),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                PieButton.ghost(
                  onPressed: () => setState(() => _showingDelegation = false),
                  label: 'رجوع لإدخال الـ PIN',
                ),
              ] else ...[
                // Masked PIN dots
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(4, (index) {
                    final filled = index < _enteredPin.length;
                    return Container(
                      width: 16,
                      height: 16,
                      margin: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: filled ? PieColors.managerAccent : PieColors.surface2,
                        border: Border.all(
                          color: filled ? PieColors.managerAccent : PieColors.border,
                          width: 2,
                        ),
                      ),
                    );
                  }),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: PieTypography.caption.copyWith(color: PieColors.stateError),
                  ),
                ],
                const SizedBox(height: 24),

                // Numeric Keypad
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 3,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 1.5,
                  children: [
                    for (final d in ['1', '2', '3', '4', '5', '6', '7', '8', '9'])
                      _buildKeyButton(d, () => _onDigit(d)),
                    _buildIconButton(Icons.vpn_key_outlined, () {
                      setState(() => _showingDelegation = true);
                    }),
                    _buildKeyButton('0', () => _onDigit('0')),
                    _buildIconButton(Icons.backspace_outlined, _onBackspace),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKeyButton(String label, VoidCallback onTap) {
    return Material(
      color: PieColors.surface2,
      borderRadius: PieRadius.borderMd,
      child: InkWell(
        onTap: onTap,
        borderRadius: PieRadius.borderMd,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: PieRadius.borderMd,
            border: Border.all(color: PieColors.border),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: PieTypography.monoHeading.copyWith(
              color: PieColors.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIconButton(IconData icon, VoidCallback onTap) {
    return Material(
      color: PieColors.surface1,
      borderRadius: PieRadius.borderMd,
      child: InkWell(
        onTap: onTap,
        borderRadius: PieRadius.borderMd,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: PieRadius.borderMd,
            border: Border.all(color: PieColors.border),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 20, color: PieColors.inkSecondary),
        ),
      ),
    );
  }
}

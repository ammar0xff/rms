import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text.dart';
import 'buttons.dart';

/// Manager PIN gate: 4 masked dots plus a tactile keypad. Returns true on a
/// correct entry, null on dismiss. Attempts and lockout live here (ephemeral
/// UI state); verification itself is the caller's job via [onVerify], so
/// this widget never touches the network or storage.
class PinGateDialog extends StatefulWidget {
  const PinGateDialog({
    super.key,
    required this.title,
    required this.onVerify,
  });

  final String title;
  final Future<bool> Function(String pin) onVerify;

  @override
  State<PinGateDialog> createState() => _PinGateDialogState();
}

class _PinGateDialogState extends State<PinGateDialog> {
  String _pin = '';
  bool _checking = false;
  bool _wrong = false;
  int _attempts = 0;
  DateTime? _lockedUntil;

  bool get _locked =>
      _lockedUntil != null && DateTime.now().isBefore(_lockedUntil!);

  Future<void> _press(String digit) async {
    if (_checking || _locked || _pin.length >= 8) return;
    setState(() {
      _pin += digit;
      _wrong = false;
    });
    if (_pin.length >= 4) await _submit();
  }

  Future<void> _submit() async {
    setState(() => _checking = true);
    final ok = await widget.onVerify(_pin);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _checking = false;
      _wrong = true;
      _pin = '';
      _attempts++;
      if (_attempts >= 3) {
        _lockedUntil = DateTime.now().add(const Duration(minutes: 5));
        _attempts = 0;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        side: const BorderSide(color: AppColors.borderStrong),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.title, style: AppText.h1),
              const SizedBox(height: 4),
              const Text('دخّل PIN المدير عشان تأكّد.',
                  style: AppText.body),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < 4; i++)
                    Container(
                      width: 16,
                      height: 16,
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i < _pin.length
                            ? AppColors.brand
                            : AppColors.surfaceSunken,
                        border: Border.all(
                          color: _wrong
                              ? AppColors.negative
                              : AppColors.borderStrong,
                        ),
                      ),
                    ),
                ],
              ),
              if (_wrong) ...[
                const SizedBox(height: 8),
                const Text('الكود غلط — جرّب تاني',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.negative)),
              ],
              if (_locked) ...[
                const SizedBox(height: 8),
                const Text('اتقفل مؤقتًا بعد ٣ محاولات',
                    textAlign: TextAlign.center,
                    style: AppText.caption),
              ],
              const SizedBox(height: 16),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1.6,
                ),
                itemCount: 12,
                itemBuilder: (context, i) {
                  if (i == 9) {
                    return _Key(
                        label: 'مسح',
                        onTap: _checking
                            ? null
                            : () => setState(() => _pin = ''));
                  }
                  if (i == 10) return _keyDigit('0');
                  if (i == 11) {
                    return _Key(
                      icon: Icons.backspace_outlined,
                      onTap: _checking || _pin.isEmpty
                          ? null
                          : () => setState(() =>
                              _pin = _pin.substring(0, _pin.length - 1)),
                    );
                  }
                  return _keyDigit('${i + 1}');
                },
              ),
              const SizedBox(height: 12),
              RmsButton(
                label: 'إلغاء',
                variant: BtnVariant.ghost,
                onPressed:
                    _checking ? null : () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _keyDigit(String digit) => _Key(
        label: digit,
        onTap: _checking ? null : () => _press(digit),
      );
}

class _Key extends StatelessWidget {
  const _Key({this.label, this.icon, this.onTap});

  final String? label;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.45 : 1,
      child: Material(
        color: AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          child: Center(
            child: icon != null
                ? Icon(icon, size: 20, color: AppColors.fgSecondary)
                : Text(label ?? '',
                    style: AppText.h1.copyWith(fontSize: 22)),
          ),
        ),
      ),
    );
  }
}

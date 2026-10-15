import 'package:flutter/material.dart';

import '../../core/config/app_version.dart';
import '../../core/di/app_services.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/surface_card.dart';
import '../../data/repositories/auth_repository.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();

  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await AppScope.of(context).auth.signInWithEmail(
            email: _email.text,
            password: _password.text,
          );
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'حصلت مشكلة غير متوقعة. جرّب تاني.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);

    return Scaffold(
      backgroundColor: AppColors.base,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.fg,
                        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                      ),
                      child: Text('R',
                          style: AppText.bodyStrong.copyWith(
                              color: AppColors.base, fontSize: 14)),
                    ),
                    const SizedBox(width: 10),
                    Text('نظام إدارة المطاعم', style: AppText.h2),
                  ],
                ),
                const SizedBox(height: 20),
                SurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('أهلاً بيك', style: AppText.h1),
                      const SizedBox(height: 4),
                      Text(
                        services.isDemo
                            ? 'وضع العرض التجريبي — أي بيانات تعمل.'
                            : 'أدخل بيانات حسابك للمتابعة.',
                        style: AppText.caption,
                      ),
                      const SizedBox(height: 18),
                      _Field(
                        controller: _email,
                        label: 'البريد الإلكتروني',
                        icon: Icons.alternate_email,
                        hint: 'name@restaurant.com',
                        keyboardType: TextInputType.emailAddress,
                        onSubmitted: (_) => _passwordFocus.requestFocus(),
                      ),
                      const SizedBox(height: 14),
                      _Field(
                        controller: _password,
                        focusNode: _passwordFocus,
                        label: 'كلمة المرور',
                        icon: Icons.lock_outline,
                        hint: '••••••••',
                        obscure: true,
                        onSubmitted: (_) => _submit(),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.negative.withValues(alpha: 0.06),
                            border: Border.all(
                                color:
                                    AppColors.negative.withValues(alpha: 0.25)),
                            borderRadius:
                                BorderRadius.circular(AppSpacing.radiusSm),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline,
                                  size: 14, color: AppColors.negative),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(_error!,
                                    style: AppText.caption.copyWith(
                                        color: AppColors.negative)),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: RmsButton(
                          label: _loading ? 'جارٍ الدخول…' : 'ادخل',
                          icon: _loading
                              ? Icons.hourglass_top
                              : Icons.login_rounded,
                          variant: BtnVariant.primary,
                          dense: false,
                          onPressed: _loading ? null : _submit,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'إصدار ${AppVersion.number}',
                  textAlign: TextAlign.center,
                  style: AppText.caption.copyWith(color: AppColors.fgGhost),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    required this.icon,
    this.hint,
    this.focusNode,
    this.keyboardType,
    this.obscure = false,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final String? hint;
  final FocusNode? focusNode;
  final TextInputType? keyboardType;
  final bool obscure;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppText.label),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          focusNode: focusNode,
          keyboardType: keyboardType,
          obscureText: obscure,
          onSubmitted: onSubmitted,
          style: AppText.bodyStrong.copyWith(fontSize: 12.5),
          cursorColor: AppColors.brand,
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            hintStyle: AppText.caption.copyWith(color: AppColors.fgGhost),
            prefixIcon: Icon(icon, size: 15, color: AppColors.fgMuted),
            prefixIconConstraints:
                const BoxConstraints(minWidth: 38, minHeight: 38),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            filled: true,
            fillColor: AppColors.surfaceSecondary,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              borderSide: BorderSide(color: AppColors.control),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              borderSide: BorderSide(color: AppColors.brand),
            ),
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';

import '../../core/di/app_services.dart';
import '../../core/sound/pie_sound_service.dart';
import '../../core/theme/pie_colors.dart';
import '../../core/theme/pie_radius.dart';
import '../../core/theme/pie_typography.dart';
import '../../core/widgets/pie_button.dart';
import '../../core/widgets/pie_card.dart';
import '../../domain/models/app_role.dart';
import '../../data/repositories/auth_repository.dart';

/// Single sign-in and account registration screen for PIE restaurant operations.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();

  bool _isSignUp = false;
  AppRole _selectedRole = AppRole.cashier;
  bool _isLoading = false;
  String? _errorMessage;
  bool _initializedDefaults = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initializedDefaults) {
      _initializedDefaults = true;
      final services = AppScope.of(context);
      // Only populate demo defaults when running in local offline demo mode
      if (services.isDemo) {
        _emailCtrl.text = 'cashier@pie.eg';
        _passCtrl.text = 'pie123456';
      }
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _signInWithRole(AppRole role) async {
    PieSoundService.instance.click();
    final email = switch (role) {
      AppRole.cashier => 'cashier@pie.eg',
      AppRole.driver => 'driver@pie.eg',
      AppRole.manager => 'manager@pie.eg',
      AppRole.developer => 'dev@pie.eg',
    };
    _emailCtrl.text = email;
    _passCtrl.text = 'pie123456';
    await _submit();
  }

  Future<void> _submit() async {
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text;

    if (email.isEmpty || pass.isEmpty) {
      PieSoundService.instance.alert();
      setState(() => _errorMessage = 'يرجى إدخال البريد الإلكتروني وكلمة المرور.');
      return;
    }

    if (_isSignUp && _nameCtrl.text.trim().isEmpty) {
      PieSoundService.instance.alert();
      setState(() => _errorMessage = 'يرجى إدخال اسم الموظف.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final auth = AppScope.of(context).auth;
    try {
      if (_isSignUp) {
        await auth.signUpWithEmail(
          email: email,
          password: pass,
          displayName: _nameCtrl.text.trim(),
          role: _selectedRole,
        );
      } else {
        await auth.signInWithEmail(
          email: email,
          password: pass,
        );
      }
      PieSoundService.instance.chime();
    } on AuthException catch (e) {
      PieSoundService.instance.alert();
      if (mounted) setState(() => _errorMessage = e.message);
    } catch (e) {
      PieSoundService.instance.alert();
      if (mounted) setState(() => _errorMessage = 'فشل تسجيل الدخول: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final isDemo = services.isDemo;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: PieColors.canvas,
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Brand Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          color: PieColors.surface2,
                          borderRadius: PieRadius.borderLg,
                          border: Border.all(color: PieColors.roleCashier, width: 1.5),
                          boxShadow: [
                            BoxShadow(
                              color: PieColors.roleCashier.withValues(alpha: 0.25),
                              blurRadius: 18,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Text(
                            'π',
                            style: TextStyle(
                              color: PieColors.roleCashier,
                              fontSize: 34,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'PIE Operations',
                            style: PieTypography.h1.copyWith(
                              color: PieColors.textPrimary,
                              letterSpacing: 1.2,
                            ),
                          ),
                          Text(
                            isDemo
                                ? 'نظام تشغيل المطاعم الميداني · الوضع التجريبي'
                                : 'نظام تشغيل المطاعم الميداني · إنتاج سحابي متصل',
                            style: PieTypography.caption.copyWith(color: PieColors.textSecondary),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),

                  // Quick One-Tap Role Selector Cards (Only in Demo Mode)
                  if (isDemo) ...[
                    Text(
                      'الدخول السريع للأدوار الميدانية (وضع تجريبي):',
                      style: PieTypography.caption.copyWith(
                        color: PieColors.textSecondary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildRoleCard(
                            role: AppRole.cashier,
                            icon: Icons.point_of_sale,
                            title: 'كاشير',
                            subtitle: 'البيع وإغلاق الوردية',
                            accent: PieColors.roleCashier,
                            onTap: () => _signInWithRole(AppRole.cashier),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildRoleCard(
                            role: AppRole.driver,
                            icon: Icons.two_wheeler,
                            title: 'طيار',
                            subtitle: 'مسار التوصيل والعهدة',
                            accent: PieColors.roleDriver,
                            onTap: () => _signInWithRole(AppRole.driver),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildRoleCard(
                            role: AppRole.manager,
                            icon: Icons.insights,
                            title: 'مدير',
                            subtitle: 'الموافقات والمخزون',
                            accent: PieColors.roleManager,
                            onTap: () => _signInWithRole(AppRole.manager),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildRoleCard(
                            role: AppRole.developer,
                            icon: Icons.terminal,
                            title: 'مسؤول نظام',
                            subtitle: 'المزامنة والتشخيص',
                            accent: PieColors.roleSystem,
                            onTap: () => _signInWithRole(AppRole.developer),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                  ],

                  // Mode Toggle (Sign In vs Sign Up)
                  Container(
                    decoration: BoxDecoration(
                      color: PieColors.surface1,
                      borderRadius: PieRadius.borderMd,
                      border: Border.all(color: PieColors.border),
                    ),
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              PieSoundService.instance.click();
                              setState(() {
                                _isSignUp = false;
                                _errorMessage = null;
                              });
                            },
                            borderRadius: PieRadius.borderSm,
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: !_isSignUp ? PieColors.surface3 : Colors.transparent,
                                borderRadius: PieRadius.borderSm,
                              ),
                              child: Center(
                                child: Text(
                                  'تسجيل الدخول',
                                  style: PieTypography.body.copyWith(
                                    fontWeight: !_isSignUp ? FontWeight.w700 : FontWeight.w500,
                                    color: !_isSignUp ? PieColors.textPrimary : PieColors.textMuted,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              PieSoundService.instance.click();
                              setState(() {
                                _isSignUp = true;
                                _errorMessage = null;
                              });
                            },
                            borderRadius: PieRadius.borderSm,
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: _isSignUp ? PieColors.surface3 : Colors.transparent,
                                borderRadius: PieRadius.borderSm,
                              ),
                              child: Center(
                                child: Text(
                                  'إنشاء حساب جديد',
                                  style: PieTypography.body.copyWith(
                                    fontWeight: _isSignUp ? FontWeight.w700 : FontWeight.w500,
                                    color: _isSignUp ? PieColors.textPrimary : PieColors.textMuted,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Auth Card
                  PieCard(
                    surface: PieColors.surface2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          _isSignUp ? 'إنشاء حساب موظف جديد' : 'تسجيل الدخول إلى المحطة',
                          style: PieTypography.h3.copyWith(color: PieColors.textPrimary),
                        ),
                        const SizedBox(height: 16),
                        if (_errorMessage != null) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: PieColors.stateError.withValues(alpha: 0.15),
                              borderRadius: PieRadius.borderMd,
                              border: Border.all(color: PieColors.stateError.withValues(alpha: 0.4)),
                            ),
                            child: Text(
                              _errorMessage!,
                              style: PieTypography.caption.copyWith(color: PieColors.stateError),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        if (_isSignUp) ...[
                          TextField(
                            controller: _nameCtrl,
                            style: PieTypography.body.copyWith(color: PieColors.textPrimary),
                            decoration: const InputDecoration(
                              labelText: 'الاسم بالكامل',
                              filled: true,
                              fillColor: PieColors.well,
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.person_outline, color: PieColors.textMuted),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text('الدور الوظيفي:', style: PieTypography.caption),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: AppRole.values.map((role) {
                              final isSelected = _selectedRole == role;
                              return ChoiceChip(
                                label: Text(role.label),
                                selected: isSelected,
                                selectedColor: PieColors.roleCashier.withValues(alpha: 0.25),
                                onSelected: (_) {
                                  PieSoundService.instance.click();
                                  setState(() => _selectedRole = role);
                                },
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 16),
                        ],
                        TextField(
                          controller: _emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          style: PieTypography.body.copyWith(color: PieColors.textPrimary),
                          decoration: const InputDecoration(
                            labelText: 'البريد الإلكتروني',
                            filled: true,
                            fillColor: PieColors.well,
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.email_outlined, color: PieColors.textMuted),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _passCtrl,
                          obscureText: true,
                          style: PieTypography.body.copyWith(color: PieColors.textPrimary),
                          decoration: const InputDecoration(
                            labelText: 'كلمة المرور',
                            filled: true,
                            fillColor: PieColors.well,
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.lock_outline, color: PieColors.textMuted),
                          ),
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          height: 48,
                          child: PieButton(
                            label: _isLoading
                                ? 'جاري التحقق...'
                                : (_isSignUp ? 'إنشاء الحساب وبدء العمل' : 'تسجيل الدخول'),
                            icon: _isSignUp ? Icons.person_add_rounded : Icons.login_rounded,
                            role: AppRole.cashier,
                            onPressed: _isLoading ? null : _submit,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRoleCard({
    required AppRole role,
    required IconData icon,
    required String title,
    required String subtitle,
    required Color accent,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: _isLoading ? null : onTap,
      borderRadius: PieRadius.borderLg,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: PieColors.surface2,
          borderRadius: PieRadius.borderLg,
          border: Border.all(color: accent.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, color: accent, size: 24),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: PieTypography.h3.copyWith(color: PieColors.textPrimary),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: PieTypography.caption.copyWith(color: PieColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

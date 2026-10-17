import 'package:flutter/material.dart';

import '../../core/di/app_services.dart';
import '../../core/theme/pie_colors.dart';
import '../../core/theme/pie_typography.dart';
import '../../core/widgets/pie_button.dart';
import '../../core/widgets/pie_card.dart';
import '../../domain/models/app_role.dart';
import '../../data/repositories/auth_repository.dart';

/// Role launcher and single sign-in screen for PIE restaurant operations.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _emailCtrl = TextEditingController(text: 'cashier@pie.eg');
  final _passCtrl = TextEditingController(text: 'pie123456');
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _signInWithRole(AppRole role) async {
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
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final auth = AppScope.of(context).auth;
    try {
      await auth.signInWithEmail(
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text,
      );
    } on AuthException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } catch (e) {
      if (mounted) setState(() => _errorMessage = 'فشل تسجيل الدخول: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: PieColors.surface2,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: PieColors.borderMuted),
                        ),
                        child: const Center(
                          child: Text(
                            'π',
                            style: TextStyle(
                              color: PieColors.roleCashier,
                              fontSize: 32,
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
                            'نظام تشغيل المطاعم الميداني · مصر والخليج',
                            style: PieTypography.caption.copyWith(color: PieColors.textSecondary),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 36),

                  // Quick One-Tap Role Selector Cards
                  Text(
                    'الدخول السريع للأدوار الميدانية (تجريبي):',
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
                  const SizedBox(height: 32),

                  // Standard Sign In Form
                  PieCard(
                    surface: PieColors.surface2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'أو تسجيل الدخول اليدوي',
                          style: PieTypography.h3.copyWith(color: PieColors.textPrimary),
                        ),
                        const SizedBox(height: 16),
                        if (_errorMessage != null) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: PieColors.stateError.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: PieColors.stateError.withValues(alpha: 0.4)),
                            ),
                            child: Text(
                              _errorMessage!,
                              style: PieTypography.caption.copyWith(color: PieColors.stateError),
                            ),
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
                            label: _isLoading ? 'جاري التحقق...' : 'تسجيل الدخول إلى المحطة',
                            icon: Icons.login,
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
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: PieColors.surface2,
          borderRadius: BorderRadius.circular(12),
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

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/di/app_services.dart';
import '../../core/sound/pie_sound_service.dart';
import '../../core/theme/pie_colors.dart';
import '../../core/theme/pie_radius.dart';
import '../../core/theme/pie_typography.dart';
import '../../core/widgets/pie_button.dart';
import '../../domain/models/app_role.dart';
import '../../data/repositories/auth_repository.dart';

/// Redesigned Single Sign-In and Staff Registration Screen for PIE Operations.
///
/// Features:
/// - Responsive split-screen presentation on desktop/tablet, adaptive card on mobile.
/// - Tactile tab switcher between Sign-In and Staff Registration.
/// - Integrated password visibility toggle and keyboard shortcuts.
/// - One-tap quick demo accounts in demo mode with full role previews.
/// - Interactive role selector during staff sign-up.
/// - 100% Arabic RTL design conforming to PIE high-contrast design system.
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
  bool _allowSignUp = true;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _signUpSub;
  AppRole _selectedRole = AppRole.cashier;
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;
  bool _initializedDefaults = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initializedDefaults) {
      _initializedDefaults = true;
      final services = AppScope.of(context);
      // Load fallback from facility settings
      services.facility?.load().then((f) {
        if (mounted) {
          setState(() {
            _allowSignUp = f.allowSignUp;
            if (!f.allowSignUp && _isSignUp) {
              _isSignUp = false;
            }
          });
        }
      });
      // Listen to public_settings/auth in Firestore
      if (services.firebaseReady) {
        _signUpSub = FirebaseFirestore.instance
            .collection('public_settings')
            .doc('auth')
            .snapshots()
            .listen((snap) {
          if (mounted && snap.exists && snap.data() != null) {
            final val = snap.data()!['allowSignUp'] as bool?;
            if (val != null) {
              setState(() {
                _allowSignUp = val;
                if (!val && _isSignUp) {
                  _isSignUp = false;
                }
              });
            }
          }
        }, onError: (_) {});
      }
      // Only populate demo defaults when running in local offline demo mode
      if (services.isDemo) {
        _emailCtrl.text = 'cashier@pie.eg';
        _passCtrl.text = 'pie123456';
      }
    }
  }

  @override
  void dispose() {
    _signUpSub?.cancel();
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

    if (_isSignUp && !_allowSignUp) {
      PieSoundService.instance.alert();
      setState(() => _errorMessage = 'التسجيل مغلق حالياً من قِبل إدارة النظام.');
      return;
    }

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
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 980;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: PieColors.canvas,
        body: isDesktop
            ? Row(
                children: [
                  // Right side in RTL: Brand & Terminal Showcase Pane
                  Expanded(
                    flex: 5,
                    child: _buildShowcasePane(isDemo),
                  ),
                  // Left side in RTL: Authentication Form Terminal
                  Expanded(
                    flex: 6,
                    child: Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 36),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 480),
                          child: _buildAuthCard(isDemo),
                        ),
                      ),
                    ),
                  ),
                ],
              )
            : Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildMobileHeader(isDemo),
                        const SizedBox(height: 24),
                        _buildAuthCard(isDemo),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  /// Showcase Pane on Desktop
  Widget _buildShowcasePane(bool isDemo) {
    return Container(
      decoration: BoxDecoration(
        color: PieColors.surface1,
        border: const Border(left: BorderSide(color: PieColors.border, width: 1)),
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            PieColors.surface1,
            PieColors.canvas,
            PieColors.cashierAccent.withValues(alpha: 0.05),
          ],
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top System Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: PieColors.surface2,
              borderRadius: PieRadius.borderSm,
              border: Border.all(color: PieColors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Color(0xFF4ADE80),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  isDemo ? 'المحطة جاهزة · الوضع التجريبي' : 'المحطة متصلة · سحابة الإنتاج الحية',
                  style: PieTypography.caption.copyWith(color: PieColors.inkSecondary),
                ),
              ],
            ),
          ),

          const Spacer(),

          // Glowing Brand Logo
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: PieColors.surface2,
              borderRadius: PieRadius.borderLg,
              border: Border.all(color: PieColors.cashierAccent, width: 2),
              boxShadow: [
                BoxShadow(
                  color: PieColors.cashierAccent.withValues(alpha: 0.3),
                  blurRadius: 28,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Center(
              child: Text(
                'π',
                style: TextStyle(
                  color: PieColors.cashierAccent,
                  fontSize: 42,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Titles
          Text(
            'PIE Operations',
            style: PieTypography.display.copyWith(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
              color: PieColors.ink,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'نظام التشغيل وإدارة العمليات الميدانية للمطاعم ونقاط البيع الفورية',
            style: PieTypography.body.copyWith(
              fontSize: 16,
              color: PieColors.inkSecondary,
            ),
          ),

          const SizedBox(height: 36),

          // Feature Highlights
          _buildFeatureRow(
            icon: const _LightningIcon(color: PieColors.cashierAccent, size: 20),
            color: PieColors.cashierAccent,
            title: 'سرعة فائقة ومعالجة فورية',
            desc: 'بناء وتمرير الطلبات وتوزيعها على شاشات المطبخ فورياً دون تأخير.',
          ),
          const SizedBox(height: 16),
          _buildFeatureRow(
            icon: const Icon(Icons.cloud_off_rounded, color: Color(0xFF38BDF8), size: 20),
            color: const Color(0xFF38BDF8),
            title: 'معمارية محلية أولاً (Offline-First)',
            desc: 'تسجيل البيع وإصدار الفواتير بدون إنترنت مع مزامنة سحابية هادئة وتلقائية.',
          ),
          const SizedBox(height: 16),
          _buildFeatureRow(
            icon: const _ShieldSecurityIcon(color: Color(0xFF4ADE80), size: 20),
            color: const Color(0xFF4ADE80),
            title: 'إدارة الأدوار والصلاحيات',
            desc: 'واجهات متخصصة لكل من الكاشير، طيار التوصيل، مدير الفرع، ومسؤول النظام.',
          ),
          const SizedBox(height: 16),
          _buildFeatureRow(
            icon: const Icon(Icons.print_rounded, color: Color(0xFFA78BFA), size: 20),
            color: const Color(0xFFA78BFA),
            title: 'طباعة حرارية متوافقة (ESC/POS)',
            desc: 'طباعة إيصالات الكاشير، تذاكر المطبخ، وبونات الدليفري، وتقارير الوردية Z.',
          ),

          const Spacer(),

          // Footer
          Text(
            'الإصدار 1.2.4 · موثق بالكامل ومعتمد تشغيلياً',
            style: PieTypography.caption.copyWith(color: PieColors.inkMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureRow({
    required Widget icon,
    required Color color,
    required String title,
    required String desc,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: PieRadius.borderMd,
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Center(child: icon),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: PieTypography.bodyStrong.copyWith(color: PieColors.ink)),
              const SizedBox(height: 2),
              Text(
                desc,
                style: PieTypography.caption.copyWith(color: PieColors.inkSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Compact Header on Mobile
  Widget _buildMobileHeader(bool isDemo) {
    return Column(
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: PieColors.surface2,
            borderRadius: PieRadius.borderLg,
            border: Border.all(color: PieColors.cashierAccent, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: PieColors.cashierAccent.withValues(alpha: 0.25),
                blurRadius: 20,
              ),
            ],
          ),
          child: const Center(
            child: Text(
              'π',
              style: TextStyle(
                color: PieColors.cashierAccent,
                fontSize: 34,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'PIE Operations',
          style: PieTypography.heading.copyWith(
            fontWeight: FontWeight.w700,
            color: PieColors.ink,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          isDemo ? 'نظام تشغيل المطاعم الميداني · الوضع التجريبي' : 'نظام تشغيل المطاعم الميداني · إنتاج سحابي متصل',
          style: PieTypography.caption.copyWith(color: PieColors.inkSecondary),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  /// Authentication Card
  Widget _buildAuthCard(bool isDemo) {
    return Container(
      decoration: BoxDecoration(
        color: PieColors.surface1,
        borderRadius: PieRadius.borderLg,
        border: Border.all(color: PieColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Segmented Mode Switcher (Sign In / Register) or Locked Header
          if (_allowSignUp)
            Container(
              decoration: BoxDecoration(
                color: PieColors.well,
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
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: !_isSignUp ? PieColors.surface3 : Colors.transparent,
                          borderRadius: PieRadius.borderSm,
                          border: Border.all(
                            color: !_isSignUp ? PieColors.cashierAccent.withValues(alpha: 0.4) : Colors.transparent,
                          ),
                        ),
                        child: Center(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.login_rounded,
                                size: 16,
                                color: !_isSignUp ? PieColors.cashierAccent : PieColors.inkMuted,
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  'تسجيل الدخول',
                                  overflow: TextOverflow.ellipsis,
                                  style: PieTypography.body.copyWith(
                                    fontWeight: !_isSignUp ? FontWeight.w700 : FontWeight.w500,
                                    color: !_isSignUp ? PieColors.ink : PieColors.inkMuted,
                                  ),
                                ),
                              ),
                            ],
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
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: _isSignUp ? PieColors.surface3 : Colors.transparent,
                          borderRadius: PieRadius.borderSm,
                          border: Border.all(
                            color: _isSignUp ? PieColors.cashierAccent.withValues(alpha: 0.4) : Colors.transparent,
                          ),
                        ),
                        child: Center(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.person_add_rounded,
                                size: 16,
                                color: _isSignUp ? PieColors.cashierAccent : PieColors.inkMuted,
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  'إنشاء حساب موظف',
                                  overflow: TextOverflow.ellipsis,
                                  style: PieTypography.body.copyWith(
                                    fontWeight: _isSignUp ? FontWeight.w700 : FontWeight.w500,
                                    color: _isSignUp ? PieColors.ink : PieColors.inkMuted,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: PieColors.well,
                borderRadius: PieRadius.borderMd,
                border: Border.all(color: PieColors.border),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        const Icon(Icons.login_rounded, size: 20, color: PieColors.cashierAccent),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'تسجيل الدخول للمحطة',
                            style: PieTypography.h3.copyWith(color: PieColors.ink),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: PieColors.stateError.withValues(alpha: 0.12),
                      borderRadius: PieRadius.borderSm,
                      border: Border.all(color: PieColors.stateError.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.lock_outline_rounded, size: 13, color: PieColors.stateError),
                        const SizedBox(width: 4),
                        Text(
                          'التسجيل مغلق',
                          style: PieTypography.caption.copyWith(
                            color: PieColors.stateError,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 24),

          // Error Notification Banner
          if (_errorMessage != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: PieColors.stateError.withValues(alpha: 0.12),
                borderRadius: PieRadius.borderMd,
                border: Border.all(color: PieColors.stateError.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded, color: PieColors.stateError, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: PieTypography.caption.copyWith(color: PieColors.stateError),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
          ],

          // Quick Demo Credentials (Only visible in Demo Mode)
          if (isDemo && !_isSignUp) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'الدخول السريع للأدوار الميدانية:',
                    style: PieTypography.caption.copyWith(
                      color: PieColors.inkSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: const BoxDecoration(
                    color: PieColors.surface2,
                    borderRadius: PieRadius.borderSm,
                  ),
                  child: Text(
                    'تجريبي',
                    style: PieTypography.caption.copyWith(fontSize: 10, color: PieColors.inkMuted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _buildRoleCard(
                    role: AppRole.cashier,
                    icon: Icons.point_of_sale_rounded,
                    title: 'كاشير',
                    subtitle: 'البيع وإغلاق الوردية',
                    accent: PieColors.cashierAccent,
                    onTap: () => _signInWithRole(AppRole.cashier),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildRoleCard(
                    role: AppRole.driver,
                    icon: Icons.two_wheeler_rounded,
                    title: 'طيار',
                    subtitle: 'مسار التوصيل والعهدة',
                    accent: const Color(0xFF38BDF8),
                    onTap: () => _signInWithRole(AppRole.driver),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _buildRoleCard(
                    role: AppRole.manager,
                    icon: Icons.admin_panel_settings_rounded,
                    title: 'مدير',
                    subtitle: 'الموافقات والمخزون',
                    accent: const Color(0xFF4ADE80),
                    onTap: () => _signInWithRole(AppRole.manager),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildRoleCard(
                    role: AppRole.developer,
                    icon: Icons.terminal_rounded,
                    title: 'مسؤول نظام',
                    subtitle: 'المزامنة والتشخيص',
                    accent: const Color(0xFFA78BFA),
                    onTap: () => _signInWithRole(AppRole.developer),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                const Expanded(child: Divider(color: PieColors.border)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    'أو الدخول بالبريد الإلكتروني',
                    style: PieTypography.caption.copyWith(color: PieColors.inkMuted),
                  ),
                ),
                const Expanded(child: Divider(color: PieColors.border)),
              ],
            ),
            const SizedBox(height: 20),
          ],

          // Registration Specific Fields
          if (_isSignUp) ...[
            Text('الاسم الكامل للموظف', style: PieTypography.caption.copyWith(color: PieColors.inkSecondary)),
            const SizedBox(height: 6),
            TextFormField(
              controller: _nameCtrl,
              textInputAction: TextInputAction.next,
              style: PieTypography.body.copyWith(color: PieColors.ink),
              decoration: const InputDecoration(
                hintText: 'مثال: حسام إبراهيم',
                filled: true,
                fillColor: PieColors.well,
                border: OutlineInputBorder(borderRadius: PieRadius.borderMd),
                prefixIcon: Icon(Icons.person_outline_rounded, color: PieColors.inkMuted),
              ),
            ),
            const SizedBox(height: 16),
            Text('الدور الوظيفي بالمطعم', style: PieTypography.caption.copyWith(color: PieColors.inkSecondary)),
            const SizedBox(height: 8),
            _buildRoleSelectionGrid(),
            const SizedBox(height: 16),
          ],

          // Email Input Field
          Text('البريد الإلكتروني', style: PieTypography.caption.copyWith(color: PieColors.inkSecondary)),
          const SizedBox(height: 6),
          TextFormField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            style: PieTypography.body.copyWith(color: PieColors.ink),
            decoration: const InputDecoration(
              hintText: 'name@pie.eg',
              filled: true,
              fillColor: PieColors.well,
              border: OutlineInputBorder(borderRadius: PieRadius.borderMd),
              prefixIcon: Icon(Icons.alternate_email_rounded, color: PieColors.inkMuted),
            ),
          ),

          const SizedBox(height: 16),

          // Password Input Field
          Text('كلمة المرور', style: PieTypography.caption.copyWith(color: PieColors.inkSecondary)),
          const SizedBox(height: 6),
          TextFormField(
            controller: _passCtrl,
            obscureText: _obscurePassword,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _submit(),
            style: PieTypography.body.copyWith(color: PieColors.ink),
            decoration: InputDecoration(
              hintText: '••••••••',
              filled: true,
              fillColor: PieColors.well,
              border: const OutlineInputBorder(borderRadius: PieRadius.borderMd),
              prefixIcon: const Icon(Icons.lock_outline_rounded, color: PieColors.inkMuted),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  color: PieColors.inkMuted,
                  size: 20,
                ),
                onPressed: () {
                  setState(() => _obscurePassword = !_obscurePassword);
                },
              ),
            ),
          ),

          const SizedBox(height: 26),

          // Primary Action CTA Button
          PieButton.primary(
            label: _isLoading
                ? 'جاري التحقق والدخول...'
                : (_isSignUp ? 'إنشاء الحساب وبدء الوردية' : 'تسجيل الدخول إلى المحطة'),
            icon: _isSignUp ? Icons.person_add_rounded : Icons.login_rounded,
            accentColor: PieColors.cashierAccent,
            height: 48,
            onPressed: _isLoading ? null : _submit,
          ),

          const SizedBox(height: 18),

          // Bottom Security Footnote
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.shield_outlined, size: 14, color: PieColors.inkMuted),
                const SizedBox(width: 6),
                Text(
                  'اتصال مشفر ومؤمن سحابياً ومحلياً',
                  style: PieTypography.caption.copyWith(fontSize: 11, color: PieColors.inkMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Interactive Role Selector Grid during Registration
  Widget _buildRoleSelectionGrid() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildSelectableRoleChip(
                role: AppRole.cashier,
                label: 'كاشير الكاونتر',
                icon: Icons.point_of_sale_rounded,
                accent: PieColors.cashierAccent,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildSelectableRoleChip(
                role: AppRole.driver,
                label: 'كابتن توصيل',
                icon: Icons.two_wheeler_rounded,
                accent: const Color(0xFF38BDF8),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildSelectableRoleChip(
                role: AppRole.manager,
                label: 'مدير الفرع',
                icon: Icons.admin_panel_settings_rounded,
                accent: const Color(0xFF4ADE80),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildSelectableRoleChip(
                role: AppRole.developer,
                label: 'مسؤول نظام',
                icon: Icons.terminal_rounded,
                accent: const Color(0xFFA78BFA),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSelectableRoleChip({
    required AppRole role,
    required String label,
    required IconData icon,
    required Color accent,
  }) {
    final isSelected = _selectedRole == role;
    return InkWell(
      onTap: () {
        PieSoundService.instance.click();
        setState(() => _selectedRole = role);
      },
      borderRadius: PieRadius.borderMd,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? accent.withValues(alpha: 0.16) : PieColors.well,
          borderRadius: PieRadius.borderMd,
          border: Border.all(
            color: isSelected ? accent : PieColors.border,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: isSelected ? accent : PieColors.inkMuted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: PieTypography.caption.copyWith(
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? PieColors.ink : PieColors.inkSecondary,
                ),
              ),
            ),
          ],
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
      borderRadius: PieRadius.borderMd,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: PieColors.well,
          borderRadius: PieRadius.borderMd,
          border: Border.all(color: accent.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, color: accent, size: 18),
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: PieTypography.bodyStrong.copyWith(color: PieColors.ink),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: PieTypography.caption.copyWith(
                fontSize: 10.5,
                color: PieColors.inkMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Standalone GPU vector lightning icon (completely independent of web font tree-shaking & caching).
class _LightningIcon extends StatelessWidget {
  const _LightningIcon({required this.color, this.size = 20});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _LightningPainter(color),
      ),
    );
  }
}

class _LightningPainter extends CustomPainter {
  const _LightningPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(w * 0.58, 0)
      ..lineTo(w * 0.18, h * 0.54)
      ..lineTo(w * 0.50, h * 0.54)
      ..lineTo(w * 0.42, h)
      ..lineTo(w * 0.82, h * 0.46)
      ..lineTo(w * 0.50, h * 0.46)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_LightningPainter oldDelegate) => oldDelegate.color != color;
}

/// Standalone GPU vector shield security icon (completely independent of web font tree-shaking & caching).
class _ShieldSecurityIcon extends StatelessWidget {
  const _ShieldSecurityIcon({required this.color, this.size = 20});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _ShieldSecurityPainter(color),
      ),
    );
  }
}

class _ShieldSecurityPainter extends CustomPainter {
  const _ShieldSecurityPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final shieldPath = Path()
      ..moveTo(w * 0.5, h * 0.05)
      ..lineTo(w * 0.90, h * 0.20)
      ..cubicTo(w * 0.90, h * 0.62, w * 0.5, h * 0.95, w * 0.5, h * 0.95)
      ..cubicTo(w * 0.5, h * 0.95, w * 0.10, h * 0.62, w * 0.10, h * 0.20)
      ..close();

    final fill = Paint()
      ..color = color.withValues(alpha: 0.22)
      ..style = PaintingStyle.fill;
    canvas.drawPath(shieldPath, fill);

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(shieldPath, stroke);

    final checkPath = Path()
      ..moveTo(w * 0.32, h * 0.48)
      ..lineTo(w * 0.45, h * 0.62)
      ..lineTo(w * 0.70, h * 0.36);

    final checkPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(checkPath, checkPaint);
  }

  @override
  bool shouldRepaint(_ShieldSecurityPainter oldDelegate) => oldDelegate.color != color;
}


import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/config/app_version.dart';
import '../../core/di/app_bootstrap.dart';
import '../../core/di/app_services.dart';
import '../../core/pwa/pwa_cache_service.dart';
import '../../core/sound/pie_sound_service.dart';
import '../../core/theme/pie_colors.dart';
import '../../core/theme/pie_radius.dart';
import '../../core/theme/pie_typography.dart';
import '../../core/widgets/pie_badge.dart';
import '../../core/widgets/pie_button.dart';
import '../../core/widgets/pie_card.dart';
import '../../core/widgets/pie_toast.dart';
import '../../domain/models/app_user.dart';
import '../../domain/models/cashier_user_settings.dart';
import '../../domain/models/order_type.dart';
import '../../domain/models/semantic_version.dart';
import '../../domain/models/update_manifest.dart';
import 'package:url_launcher/url_launcher.dart';

/// Screen: Cashier Settings & Personal Profile (`إعدادات الكاشير`)
///
/// Dedicated user-level workspace for cashiers to:
/// 1. Edit their personal user information (display name, update password).
/// 2. View device platform status (Mobile vs Desktop, viewport metrics, app version, update check).
/// 3. Configure user-level preferences (sound effects, haptic touch, default order type,
///    auto-open receipt preview, and quick cash tenders) without affecting global facility settings.
class CashierSettingsScreen extends StatefulWidget {
  const CashierSettingsScreen({super.key});

  @override
  State<CashierSettingsScreen> createState() => _CashierSettingsScreenState();
}

class _CashierSettingsScreenState extends State<CashierSettingsScreen> {
  // User profile controllers
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _newPasswordCtrl = TextEditingController();
  final TextEditingController _confirmPasswordCtrl = TextEditingController();
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;
  bool _isSavingProfile = false;
  String _branchName = 'الفرع الرئيسي';

  // Platform & update check state
  bool _isCheckingUpdates = false;
  bool _isClearingCache = false;
  String? _updateCheckMessage;
  UpdateManifest? _availableUpdateManifest;

  // Cashier user preferences state (User-level, NOT global)
  bool _isLoadingPreferences = true;
  bool _isSavingPreferences = false;
  CashierUserSettings _userSettings = const CashierUserSettings();

  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _initData();
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _newPasswordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  Future<void> _initData() async {
    final services = AppScope.of(context);
    final user = services.auth.currentUser;

    if (user != null && user.displayName != null && user.displayName!.isNotEmpty) {
      _nameCtrl.text = user.displayName!;
    } else if (user != null && user.email != null) {
      _nameCtrl.text = user.email!.split('@').first;
    }

    if (services.facility != null) {
      services.facility!.load().then((facility) {
        if (mounted && facility.activeBranchName.isNotEmpty) {
          setState(() => _branchName = facility.activeBranchName);
        }
      });
    }

    final loadedSettings = await CashierUserSettings.load(services.database, user?.uid);
    if (mounted) {
      setState(() {
        _userSettings = loadedSettings;
        _isLoadingPreferences = false;
      });
    }
  }

  Future<void> _saveProfile(AppServices services, AppUser? user) async {
    final newName = _nameCtrl.text.trim();
    final newPass = _newPasswordCtrl.text.trim();
    final confirmPass = _confirmPasswordCtrl.text.trim();

    if (newName.isEmpty) {
      _showFeedback(message: 'يرجى إدخال اسم المستخدم الظاهر', isError: true);
      return;
    }

    if (newPass.isNotEmpty) {
      if (newPass.length < 6) {
        _showFeedback(message: 'يجب ألا تقل كلمة المرور عن 6 أحرف', isError: true);
        return;
      }
      if (newPass != confirmPass) {
        _showFeedback(message: 'كلمتا المرور غير متطابقتين', isError: true);
        return;
      }
    }

    setState(() => _isSavingProfile = true);
    PieSoundService.instance.click();

    try {
      await services.auth.updateProfile(
        displayName: newName,
        newPassword: newPass.isNotEmpty ? newPass : null,
      );

      _newPasswordCtrl.clear();
      _confirmPasswordCtrl.clear();

      PieSoundService.instance.chime();
      _showFeedback(message: 'تم تحديث البيانات الشخصية بنجاح', isError: false);
    } catch (e) {
      PieSoundService.instance.alert();
      _showFeedback(
        message: 'تعذر تحديث البيانات: ${e.toString().replaceAll('Exception:', '').trim()}',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _isSavingProfile = false);
      }
    }
  }

  Future<void> _saveUserSettings(AppServices services, AppUser? user) async {
    setState(() => _isSavingPreferences = true);
    PieSoundService.instance.click();

    try {
      await CashierUserSettings.save(services.database, user?.uid, _userSettings);
      PieSoundService.instance.chime();
      _showFeedback(message: 'تم حفظ تفضيلات الكاشير بنجاح', isError: false);
    } catch (e) {
      PieSoundService.instance.alert();
      _showFeedback(message: 'تعذر حفظ التفضيلات: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isSavingPreferences = false);
      }
    }
  }

  Future<void> _checkForUpdates(AppServices services) async {
    setState(() {
      _isCheckingUpdates = true;
      _updateCheckMessage = null;
      _availableUpdateManifest = null;
    });
    PieSoundService.instance.click();

    String message = 'أنت تعمل حالياً على أحدث إصدار متوافق لنظام التشغيل (v${AppVersion.number}). النظام يعمل بكامل الكفاءة.';
    UpdateManifest? foundManifest;

    try {
      if (services.updateRuntime != null) {
        try {
          await services.updateRuntime!.manifest();
        } catch (_) {}
      }
      if (services.updates != null) {
        final manifest = await services.updates!.cached();
        if (manifest != null) {
          final remote = SemanticVersion.tryParse(manifest.version);
          final current = SemanticVersion.tryParse(AppVersion.number);
          if (remote != null && current != null && remote > current) {
            foundManifest = manifest;
            message = 'يوجد إصدار أحدث متوفر للترقية: v${manifest.version} (الإصدار الحالي v${AppVersion.number}).';
          }
        }
      }
    } catch (_) {}

    await Future<void>.delayed(const Duration(milliseconds: 600));

    if (mounted) {
      setState(() {
        _isCheckingUpdates = false;
        _updateCheckMessage = message;
        _availableUpdateManifest = foundManifest;
      });
      PieSoundService.instance.chime();
    }
  }

  Future<void> _clearBrowserCache() async {
    setState(() => _isClearingCache = true);
    PieSoundService.instance.click();
    _showFeedback(
      message: 'جاري تنظيف كاش المتصفح وقاعدة البيانات وتثبيت أحدث كود للنظام وإعادة التحميل...',
      isError: false,
    );
    final db = AppScope.of(context).database;
    if (db != null) {
      await purgeLegacyDemoData(db);
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
    PwaCacheService.instance.clearCacheAndReload();
    if (mounted) {
      setState(() => _isClearingCache = false);
    }
  }

  void _showFeedback({required String message, required bool isError}) {
    if (!mounted) return;
    PieToast.show(
      context,
      message,
      isError: isError,
      isSuccess: !isError,
    );
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final user = services.auth.currentUser;
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final screenHeight = mediaQuery.size.height;

    // Detect platform: desktop vs mobile
    final isDesktopPlatform = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux);

    // Responsive view classification
    final isDesktopLayout = isDesktopPlatform || (kIsWeb && screenWidth >= 800);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: PieColors.canvas,
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 880),
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: isDesktopLayout ? 20 : 12,
                vertical: isDesktopLayout ? 24 : 16,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Top Title & Intro
                  _buildHeader(user, isDesktopLayout),
                  const SizedBox(height: 20),

                  // Section 1: User Info to Edit
                  _buildUserProfileSection(services, user, isDesktopLayout),
                  const SizedBox(height: 24),

                  // Section 2: Updates (Mobile / Desktop)
                  _buildUpdatesAndPlatformSection(
                    services: services,
                    isDesktopLayout: isDesktopLayout,
                    screenWidth: screenWidth,
                    screenHeight: screenHeight,
                    isWeb: kIsWeb,
                  ),
                  const SizedBox(height: 24),

                  // Section 3: User Settings (User level, not global)
                  _buildUserSettingsSection(services, user, isDesktopLayout),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(AppUser? user, bool isDesktopLayout) {
    final displayName = (user?.displayName != null && user!.displayName!.isNotEmpty)
        ? user.displayName!
        : (user?.email?.split('@').first ?? 'الكاشير');

    final iconSize = isDesktopLayout ? 52.0 : 42.0;

    return Row(
      children: [
        Container(
          width: iconSize,
          height: iconSize,
          decoration: BoxDecoration(
            color: PieColors.cashierAccent.withValues(alpha: 0.15),
            shape: BoxShape.circle,
            border: Border.all(color: PieColors.cashierAccent.withValues(alpha: 0.4)),
          ),
          child: Icon(
            Icons.manage_accounts_rounded,
            color: PieColors.cashierAccent,
            size: isDesktopLayout ? 28 : 22,
          ),
        ),
        SizedBox(width: isDesktopLayout ? 16 : 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'إعدادات الكاشير وملفي الشخصي',
                style: (isDesktopLayout ? PieTypography.h2 : PieTypography.heading).copyWith(
                  color: PieColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'إدارة بيانات الحساب الشخصي للكاشير ($displayName)، ومواصفات الجهاز، والتفضيلات الفردية.',
                style: PieTypography.caption.copyWith(color: PieColors.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildUserProfileSection(AppServices services, AppUser? user, bool isDesktopLayout) {
    return PieCard(
      surface: PieColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            icon: Icons.person_rounded,
            title: 'بيانات المستخدم والحساب',
            badge: PieBadge(
              label: 'كاشير معتمد',
              color: PieColors.cashierAccent,
              backgroundColor: PieColors.cashierAccent.withValues(alpha: 0.15),
            ),
            isDesktopLayout: isDesktopLayout,
          ),
          const SizedBox(height: 6),
          Text(
            'يمكنك تحديث اسمك الظاهر في فواتير البيع أو تعديل كلمة المرور الخاصة بحسابك.',
            style: PieTypography.caption.copyWith(color: PieColors.textSecondary),
          ),
          const Divider(height: 28, color: PieColors.border),

          // User details chips
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _buildInfoPill(
                icon: Icons.alternate_email_rounded,
                label: 'البريد / المعرف',
                value: user?.email ?? 'غير محدد',
              ),
              _buildInfoPill(
                icon: Icons.badge_outlined,
                label: 'الدور التشغيلي',
                value: user?.role.label ?? 'كاشير',
              ),
              _buildInfoPill(
                icon: Icons.storefront_rounded,
                label: 'الفرع النشط',
                value: _branchName,
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Editable Display Name
          Text(
            'الاسم الظاهر للكاشير (يطبع على الإيصالات وسجل الورديات)',
            style: PieTypography.body.copyWith(fontWeight: FontWeight.w600, color: PieColors.textPrimary),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _nameCtrl,
            style: PieTypography.body.copyWith(color: PieColors.textPrimary),
            decoration: const InputDecoration(
              hintText: 'اكتب اسمك الكامل أو اسم العمل',
              prefixIcon: Icon(Icons.edit_outlined, color: PieColors.inkSecondary),
              filled: true,
              fillColor: PieColors.surface2,
              border: OutlineInputBorder(
                borderRadius: PieRadius.borderMd,
                borderSide: BorderSide(color: PieColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: PieRadius.borderMd,
                borderSide: BorderSide(color: PieColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: PieRadius.borderMd,
                borderSide: BorderSide(color: PieColors.cashierAccent, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Password change section
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: PieColors.surface2,
              borderRadius: PieRadius.borderMd,
              border: Border.all(color: PieColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.lock_reset_rounded, color: PieColors.cashierAccent, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'تغيير كلمة المرور (اختياري)',
                        style: PieTypography.body.copyWith(fontWeight: FontWeight.bold, color: PieColors.textPrimary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'اترك الحقول فارغة إذا كنت لا ترغب في تغيير كلمة المرور الحالية.',
                  style: PieTypography.caption.copyWith(color: PieColors.textSecondary),
                ),
                const SizedBox(height: 14),
                if (isDesktopLayout)
                  Row(
                    children: [
                      Expanded(child: _buildNewPasswordField()),
                      const SizedBox(width: 12),
                      Expanded(child: _buildConfirmPasswordField()),
                    ],
                  )
                else
                  Column(
                    children: [
                      _buildNewPasswordField(),
                      const SizedBox(height: 12),
                      _buildConfirmPasswordField(),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Save button
          if (isDesktopLayout)
            Align(
              alignment: Alignment.centerLeft,
              child: PieButton.primary(
                label: _isSavingProfile ? 'جاري الحفظ...' : 'حفظ البيانات الشخصية',
                icon: Icons.save_rounded,
                onPressed: _isSavingProfile ? null : () => _saveProfile(services, user),
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              child: PieButton.primary(
                label: _isSavingProfile ? 'جاري الحفظ...' : 'حفظ البيانات الشخصية',
                icon: Icons.save_rounded,
                onPressed: _isSavingProfile ? null : () => _saveProfile(services, user),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildNewPasswordField() {
    return TextFormField(
      controller: _newPasswordCtrl,
      obscureText: _obscureNewPassword,
      style: PieTypography.body.copyWith(color: PieColors.textPrimary),
      decoration: InputDecoration(
        labelText: 'كلمة المرور الجديدة',
        prefixIcon: const Icon(Icons.lock_outline, color: PieColors.inkSecondary),
        suffixIcon: IconButton(
          icon: Icon(
            _obscureNewPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            color: PieColors.inkSecondary,
          ),
          onPressed: () => setState(() => _obscureNewPassword = !_obscureNewPassword),
        ),
        filled: true,
        fillColor: PieColors.surface,
        border: const OutlineInputBorder(borderRadius: PieRadius.borderMd),
      ),
    );
  }

  Widget _buildConfirmPasswordField() {
    return TextFormField(
      controller: _confirmPasswordCtrl,
      obscureText: _obscureConfirmPassword,
      style: PieTypography.body.copyWith(color: PieColors.textPrimary),
      decoration: InputDecoration(
        labelText: 'تأكيد كلمة المرور',
        prefixIcon: const Icon(Icons.lock_clock_outlined, color: PieColors.inkSecondary),
        suffixIcon: IconButton(
          icon: Icon(
            _obscureConfirmPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            color: PieColors.inkSecondary,
          ),
          onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
        ),
        filled: true,
        fillColor: PieColors.surface,
        border: const OutlineInputBorder(borderRadius: PieRadius.borderMd),
      ),
    );
  }

  Widget _buildUpdatesAndPlatformSection({
    required AppServices services,
    required bool isDesktopLayout,
    required double screenWidth,
    required double screenHeight,
    required bool isWeb,
  }) {
    final osName = isWeb
        ? 'متصفح الويب (Web PWA)'
        : (defaultTargetPlatform == TargetPlatform.android
            ? 'نظام أندرويد (Android)'
            : (defaultTargetPlatform == TargetPlatform.iOS
                ? 'نظام أبل (iOS)'
                : (defaultTargetPlatform == TargetPlatform.windows
                    ? 'ويندوز (Windows)'
                    : (defaultTargetPlatform == TargetPlatform.macOS
                        ? 'ماك (macOS)'
                        : 'لينكس (Linux)'))));

    return PieCard(
      surface: PieColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            icon: isDesktopLayout ? Icons.desktop_windows_rounded : Icons.smartphone_rounded,
            title: 'التحديثات ونوع الجهاز (Mobile / Desktop)',
            badge: PieBadge(
              label: isDesktopLayout ? 'جهاز كمبيوتر مكتبي' : 'جهاز محمول / تابلت',
              color: isDesktopLayout ? PieColors.managerAccent : PieColors.cashierAccent,
              backgroundColor: (isDesktopLayout ? PieColors.managerAccent : PieColors.cashierAccent).withValues(alpha: 0.15),
            ),
            isDesktopLayout: isDesktopLayout,
          ),
          const SizedBox(height: 6),
          Text(
            'فحص بيئة تشغيل الكاشير وإصدار التطبيق والتحقق من آخر التحديثات المتوفرة.',
            style: PieTypography.caption.copyWith(color: PieColors.textSecondary),
          ),
          const Divider(height: 28, color: PieColors.border),

          // Platform details card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: PieColors.surface2,
              borderRadius: PieRadius.borderMd,
              border: Border.all(color: PieColors.border),
            ),
            child: Column(
              children: [
                if (isDesktopLayout)
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: PieColors.cashierAccent.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.computer_rounded,
                          color: PieColors.cashierAccent,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'وضع العرض المكتبي (Desktop Viewport)',
                              style: PieTypography.body.copyWith(fontWeight: FontWeight.bold, color: PieColors.textPrimary),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'بيئة النظام: $osName | أبعاد الشاشة: ${screenWidth.toInt()} × ${screenHeight.toInt()} بكسل',
                              style: PieTypography.caption.copyWith(color: PieColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: PieColors.surface3,
                          borderRadius: PieRadius.borderSm,
                          border: Border.all(color: PieColors.border),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.mouse_rounded,
                              size: 16,
                              color: PieColors.inkSecondary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'فأرة وكيبورد',
                              style: PieTypography.caption.copyWith(color: PieColors.inkSecondary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: PieColors.cashierAccent.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.phone_android_rounded,
                              color: PieColors.cashierAccent,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'وضع العرض المحمول (Mobile Viewport)',
                                  style: PieTypography.bodyStrong.copyWith(color: PieColors.textPrimary),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'بيئة النظام: $osName',
                                  style: PieTypography.caption.copyWith(color: PieColors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: PieColors.surface3,
                              borderRadius: PieRadius.borderSm,
                              border: Border.all(color: PieColors.border),
                            ),
                            child: Text(
                              'الأبعاد: ${screenWidth.toInt()} × ${screenHeight.toInt()} px',
                              style: PieTypography.caption.copyWith(color: PieColors.inkSecondary),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: PieColors.surface3,
                              borderRadius: PieRadius.borderSm,
                              border: Border.all(color: PieColors.border),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.touch_app_rounded,
                                  size: 14,
                                  color: PieColors.inkSecondary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'لمس محمول',
                                  style: PieTypography.caption.copyWith(color: PieColors.inkSecondary),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                const SizedBox(height: 14),
                const Divider(height: 1, color: PieColors.border),
                const SizedBox(height: 14),

                // Version numbers
                Wrap(
                  spacing: 20,
                  runSpacing: 12,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('رقم الإصدار المثبت', style: PieTypography.caption.copyWith(color: PieColors.textSecondary)),
                        const SizedBox(height: 2),
                        Text('v${AppVersion.number}', style: PieTypography.body.copyWith(fontWeight: FontWeight.bold, color: PieColors.textPrimary)),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('رقم البناء (Build)', style: PieTypography.caption.copyWith(color: PieColors.textSecondary)),
                        const SizedBox(height: 2),
                        Text('#${AppVersion.build}', style: PieTypography.body.copyWith(fontWeight: FontWeight.bold, color: PieColors.textPrimary)),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('قناة التحديث', style: PieTypography.caption.copyWith(color: PieColors.textSecondary)),
                        const SizedBox(height: 2),
                        Text(AppVersion.channel.toUpperCase(), style: PieTypography.body.copyWith(fontWeight: FontWeight.bold, color: PieColors.cashierAccent)),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('مخطط قاعدة البيانات', style: PieTypography.caption.copyWith(color: PieColors.textSecondary)),
                        const SizedBox(height: 2),
                        Text('Schema v${AppVersion.localSchemaVersion}', style: PieTypography.body.copyWith(fontWeight: FontWeight.bold, color: PieColors.textPrimary)),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          if (_updateCheckMessage != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: PieColors.surface2,
                borderRadius: PieRadius.borderMd,
                border: Border.all(color: PieColors.cashierAccent.withValues(alpha: 0.5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.check_circle_outline_rounded, color: PieColors.cashierAccent, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _updateCheckMessage!,
                          style: PieTypography.body.copyWith(color: PieColors.cashierAccent),
                        ),
                      ),
                    ],
                  ),
                  if (_availableUpdateManifest != null) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: 38,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.download_rounded, size: 18),
                        label: Text(
                          'تحميل التحديث الآن (v${_availableUpdateManifest!.version})',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: PieColors.cashierAccent,
                          foregroundColor: Colors.white,
                          shape: const RoundedRectangleBorder(borderRadius: PieRadius.borderSm),
                        ),
                        onPressed: () async {
                          final ref = _availableUpdateManifest!.artifact.reference;
                          final uri = Uri.tryParse(ref) ??
                              Uri.parse('https://github.com/ammar0xff/rms/releases/tag/v${_availableUpdateManifest!.version}');
                          await launchUrl(uri, mode: LaunchMode.externalApplication);
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Update check actions
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              PieButton.primary(
                label: _isCheckingUpdates ? 'جاري الفحص...' : 'فحص التحديثات المتاحة',
                icon: Icons.system_update_alt_rounded,
                onPressed: _isCheckingUpdates ? null : () => _checkForUpdates(services),
              ),
              if (isWeb)
                PieButton.secondary(
                  label: _isClearingCache ? 'جاري التحديث...' : 'تحديث كاش المتصفح (PWA)',
                  icon: Icons.refresh_rounded,
                  onPressed: _isClearingCache ? null : _clearBrowserCache,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildUserSettingsSection(AppServices services, AppUser? user, bool isDesktopLayout) {
    if (_isLoadingPreferences) {
      return const PieCard(
        surface: PieColors.surface,
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: CircularProgressIndicator(color: PieColors.cashierAccent),
          ),
        ),
      );
    }

    return PieCard(
      surface: PieColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            icon: Icons.tune_rounded,
            title: 'تفضيلات الكاشير الشخصية (User-Level Settings)',
            badge: const PieBadge(
              label: 'مستوى المستخدم فقط',
              color: PieColors.inkSecondary,
              backgroundColor: PieColors.surface2,
            ),
            isDesktopLayout: isDesktopLayout,
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: PieColors.surface2,
              borderRadius: PieRadius.borderSm,
              border: Border.all(color: PieColors.border),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded, color: PieColors.cashierAccent, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'هذه التفضيلات خاصة بك فقط على هذا الجهاز، ولا تغيّر إعدادات المنشأة العامة أو حسابات الكاشيرات الآخرين.',
                    style: PieTypography.caption.copyWith(color: PieColors.textSecondary),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 28, color: PieColors.border),

          // Setting 1: Sound Effects
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(
              'التأثيرات الصوتية (Sound Effects)',
              style: PieTypography.body.copyWith(fontWeight: FontWeight.bold, color: PieColors.textPrimary),
            ),
            subtitle: Text(
              'تشغيل نقرات وإشعارات صوتية سريعة عند إضافة الأصناف وتأكيد الدفع وتقفيل الوردية.',
              style: PieTypography.caption.copyWith(color: PieColors.textSecondary),
            ),
            value: _userSettings.soundEffects,
            activeTrackColor: PieColors.cashierAccent,
            onChanged: (val) {
              setState(() {
                _userSettings = _userSettings.copyWith(soundEffects: val);
              });
              PieSoundService.instance.enabled = val;
              if (val) PieSoundService.instance.pop();
            },
          ),
          if (_userSettings.soundEffects)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () {
                    PieSoundService.instance.chime();
                  },
                  icon: const Icon(Icons.volume_up_rounded, size: 18, color: PieColors.cashierAccent),
                  label: Text(
                    'تجربة الصوت التفاعلي',
                    style: PieTypography.caption.copyWith(color: PieColors.cashierAccent, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          const Divider(height: 20, color: PieColors.border),

          // Setting 2: Haptic Touch
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(
              'الاهتزاز اللمسي (Haptic Feedback)',
              style: PieTypography.body.copyWith(fontWeight: FontWeight.bold, color: PieColors.textPrimary),
            ),
            subtitle: Text(
              'نبضة اهتزاز خفيفة عند الضغط على الأزرار وشاشات اللمس للأجهزة المتوافقة.',
              style: PieTypography.caption.copyWith(color: PieColors.textSecondary),
            ),
            value: _userSettings.hapticFeedback,
            activeTrackColor: PieColors.cashierAccent,
            onChanged: (val) {
              setState(() {
                _userSettings = _userSettings.copyWith(hapticFeedback: val);
              });
              if (_userSettings.soundEffects) PieSoundService.instance.pop();
            },
          ),
          const Divider(height: 20, color: PieColors.border),

          // Setting 3: Default Order Type
          Text(
            'نوع الطلب الافتراضي عند فتح سلة جديدة',
            style: PieTypography.body.copyWith(fontWeight: FontWeight.bold, color: PieColors.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            'يتم اختيار هذا النوع تلقائياً عند بدء كل أوردر جديد لتسريع الخدمة.',
            style: PieTypography.caption.copyWith(color: PieColors.textSecondary),
          ),
          const SizedBox(height: 10),
          _buildOrderTypeSelector(isDesktopLayout),
          const Divider(height: 24, color: PieColors.border),

          // Setting 4: Auto Open Receipt
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(
              'عرض الإيصال تلقائياً بعد نجاح الدفع (Auto-Open Receipt)',
              style: PieTypography.body.copyWith(fontWeight: FontWeight.bold, color: PieColors.textPrimary),
            ),
            subtitle: Text(
              'فتح نافذة الفاتورة والطباعة الفورية تلقائياً بمجرد إتمام تحصيل الطلب.',
              style: PieTypography.caption.copyWith(color: PieColors.textSecondary),
            ),
            value: _userSettings.autoOpenReceipt,
            activeTrackColor: PieColors.cashierAccent,
            onChanged: (val) {
              setState(() {
                _userSettings = _userSettings.copyWith(autoOpenReceipt: val);
              });
              if (_userSettings.soundEffects) PieSoundService.instance.pop();
            },
          ),
          const Divider(height: 20, color: PieColors.border),

          // Setting 5: Fast Checkout Auto-Clear
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(
              'تفريغ السلة التلقائي بعد إتمام الدفع (Fast Checkout Auto-Clear)',
              style: PieTypography.body.copyWith(fontWeight: FontWeight.bold, color: PieColors.textPrimary),
            ),
            subtitle: Text(
              'تفريغ السلة وإعادتها لوضع الاستعداد لطلب العميل القادم مباشرة دون الحاجة لضغط تفريغ يدوي.',
              style: PieTypography.caption.copyWith(color: PieColors.textSecondary),
            ),
            value: _userSettings.fastCheckoutAutoClear,
            activeTrackColor: PieColors.cashierAccent,
            onChanged: (val) {
              setState(() {
                _userSettings = _userSettings.copyWith(fastCheckoutAutoClear: val);
              });
              if (_userSettings.soundEffects) PieSoundService.instance.pop();
            },
          ),
          const Divider(height: 20, color: PieColors.border),

          // Setting 6: Compact Grid
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(
              'العرض المدمج للأصناف في نقطة البيع (Compact POS Grid)',
              style: PieTypography.body.copyWith(fontWeight: FontWeight.bold, color: PieColors.textPrimary),
            ),
            subtitle: Text(
              'تقليص حجم بطاقات الأصناف لعرض عدد أكبر من المأكولات والمشروبات على الشاشة في نفس الوقت.',
              style: PieTypography.caption.copyWith(color: PieColors.textSecondary),
            ),
            value: _userSettings.compactGridView,
            activeTrackColor: PieColors.cashierAccent,
            onChanged: (val) {
              setState(() {
                _userSettings = _userSettings.copyWith(compactGridView: val);
              });
              if (_userSettings.soundEffects) PieSoundService.instance.pop();
            },
          ),
          const SizedBox(height: 24),

          // Save Settings button
          if (isDesktopLayout)
            Align(
              alignment: Alignment.centerLeft,
              child: PieButton.primary(
                label: _isSavingPreferences ? 'جاري الحفظ...' : 'حفظ تفضيلات الكاشير',
                icon: Icons.check_rounded,
                onPressed: _isSavingPreferences ? null : () => _saveUserSettings(services, user),
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              child: PieButton.primary(
                label: _isSavingPreferences ? 'جاري الحفظ...' : 'حفظ تفضيلات الكاشير',
                icon: Icons.check_rounded,
                onPressed: _isSavingPreferences ? null : () => _saveUserSettings(services, user),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOrderTypeSelector(bool isDesktop) {
    final types = [
      (OrderType.takeaway, 'تيك أواي (استلام)', Icons.shopping_bag_outlined),
      (OrderType.delivery, 'توصيل منازل', Icons.delivery_dining_outlined),
    ];

    if (isDesktop) {
      return SegmentedButton<OrderType>(
        segments: types.map((t) {
          return ButtonSegment<OrderType>(
            value: t.$1,
            label: Text(t.$2),
            icon: Icon(t.$3, size: 18),
          );
        }).toList(),
        selected: {_userSettings.defaultOrderType},
        onSelectionChanged: (selected) {
          setState(() {
            _userSettings = _userSettings.copyWith(defaultOrderType: selected.first);
          });
          if (_userSettings.soundEffects) PieSoundService.instance.click();
        },
      );
    }

    // Mobile-friendly responsive wrap of choice buttons
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: types.map((t) {
        final isSelected = _userSettings.defaultOrderType == t.$1;
        return InkWell(
          borderRadius: PieRadius.borderMd,
          onTap: () {
            setState(() {
              _userSettings = _userSettings.copyWith(defaultOrderType: t.$1);
            });
            if (_userSettings.soundEffects) PieSoundService.instance.click();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected ? PieColors.cashierAccent.withValues(alpha: 0.15) : PieColors.surface2,
              borderRadius: PieRadius.borderMd,
              border: Border.all(
                color: isSelected ? PieColors.cashierAccent : PieColors.border,
                width: isSelected ? 1.5 : 1.0,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  t.$3,
                  size: 18,
                  color: isSelected ? PieColors.cashierAccent : PieColors.inkSecondary,
                ),
                const SizedBox(width: 8),
                Text(
                  t.$2,
                  style: PieTypography.body.copyWith(
                    color: isSelected ? PieColors.cashierAccent : PieColors.textPrimary,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSectionHeader({
    required IconData icon,
    required String title,
    required Widget badge,
    required bool isDesktopLayout,
  }) {
    if (isDesktopLayout) {
      return Row(
        children: [
          Icon(icon, color: PieColors.cashierAccent, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: PieTypography.h3.copyWith(color: PieColors.textPrimary),
            ),
          ),
          const SizedBox(width: 8),
          badge,
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: PieColors.cashierAccent, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: PieTypography.bodyStrong.copyWith(
                  color: PieColors.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        badge,
      ],
    );
  }

  Widget _buildInfoPill({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 360),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: PieColors.surface2,
        borderRadius: PieRadius.borderMd,
        border: Border.all(color: PieColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: PieColors.cashierAccent),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: PieTypography.caption.copyWith(color: PieColors.textSecondary),
          ),
          Flexible(
            child: Text(
              value,
              style: PieTypography.caption.copyWith(color: PieColors.textPrimary, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }
}

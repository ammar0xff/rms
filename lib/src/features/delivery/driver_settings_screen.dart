import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
import '../../domain/models/driver_user_settings.dart';
import '../../domain/models/semantic_version.dart';
import '../../domain/models/update_manifest.dart';
import '../system/widgets/in_app_update_dialog.dart';
import 'driver_identity_service.dart';

/// Screen: Driver Settings & Personal Preferences (`إعدادات الكابتن`)
///
/// Dedicated user-level workspace for delivery couriers to:
/// 1. Edit personal user information (display name, update password).
/// 2. View device platform status (Mobile vs Desktop, viewport metrics, app version, update check).
/// 3. Configure user-level driving & navigation preferences (vehicle type, 3D Cockpit HUD vs Google Maps,
///    sound effects, tactile feedback, speed limit alerts) without affecting global facility settings.
class DriverSettingsScreen extends StatefulWidget {
  const DriverSettingsScreen({super.key});

  @override
  State<DriverSettingsScreen> createState() => _DriverSettingsScreenState();
}

class _DriverSettingsScreenState extends State<DriverSettingsScreen> {
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

  // Driver user preferences state (User-level, NOT global)
  bool _isLoadingPreferences = true;
  bool _isSavingPreferences = false;
  DriverUserSettings _driverSettings = const DriverUserSettings();

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
    } else if (DriverSession.instance.activeDriverName != null) {
      _nameCtrl.text = DriverSession.instance.activeDriverName!;
    }

    if (services.facility != null) {
      services.facility!.load().then((facility) {
        if (mounted && facility.activeBranchName.isNotEmpty) {
          setState(() => _branchName = facility.activeBranchName);
        }
      });
    }

    final loadedSettings = await DriverUserSettings.load(services.database, user?.uid);
    if (mounted) {
      setState(() {
        _driverSettings = loadedSettings;
        _isLoadingPreferences = false;
      });
    }
  }

  Future<void> _saveProfile(AppServices services, AppUser? user) async {
    final newName = _nameCtrl.text.trim();
    final newPass = _newPasswordCtrl.text.trim();
    final confirmPass = _confirmPasswordCtrl.text.trim();

    if (newName.isEmpty) {
      _showFeedback(message: 'يرجى إدخال اسم الكابتن الظاهر', isError: true);
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

      DriverSession.instance.activeDriverName = newName;
      _newPasswordCtrl.clear();
      _confirmPasswordCtrl.clear();

      PieSoundService.instance.chime();
      _showFeedback(message: 'تم حفظ بيانات الحساب بنجاح', isError: false);
    } catch (e) {
      PieSoundService.instance.alert();
      _showFeedback(
        message: 'تعذر تحديث البيانات: ${e.toString().replaceAll('Exception:', '').trim()}',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _isSavingProfile = false);
    }
  }

  Future<void> _savePreferences(AppServices services) async {
    setState(() => _isSavingPreferences = true);
    PieSoundService.instance.click();

    try {
      final user = services.auth.currentUser;
      await DriverUserSettings.save(services.database, user?.uid, _driverSettings);
      PieSoundService.instance.chime();
      _showFeedback(message: 'تم حفظ تفضيلات القيادة بنجاح', isError: false);
    } catch (e) {
      PieSoundService.instance.alert();
      _showFeedback(message: 'تعذر حفظ التفضيلات: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSavingPreferences = false);
    }
  }

  Future<void> _checkForUpdates(AppServices services) async {
    setState(() {
      _isCheckingUpdates = true;
      _updateCheckMessage = null;
      _availableUpdateManifest = null;
    });

    PieSoundService.instance.click();

    String message =
        'أنت تعمل حالياً على أحدث إصدار متوافق لنظام التشغيل (v${AppVersion.number}). النظام يعمل بكامل الكفاءة.';
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
            message =
                'يوجد إصدار أحدث متوفر للترقية: v${manifest.version} (الإصدار الحالي v${AppVersion.number}).';
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
    final media = MediaQuery.of(context);
    final isMobile = media.size.width < 768;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: PieColors.surface1,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 16 : 32,
              vertical: 20,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                _buildHeader(isMobile),
                const SizedBox(height: 20),

                // Section 1: User Profile & Security
                _buildProfileCard(services, user, isMobile),
                const SizedBox(height: 20),

                // Section 2: Driver & Navigation Preferences
                _buildDriverPreferencesCard(services, isMobile),
                const SizedBox(height: 20),

                // Section 3: Platform Environment & Updates
                _buildPlatformAndUpdatesCard(services, isMobile),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isMobile) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: PieColors.driverSurface,
            borderRadius: PieRadius.borderMd,
            border: Border.all(color: PieColors.driverBorder, width: 1.5),
          ),
          child: const Icon(
            Icons.tune_rounded,
            color: PieColors.driverAccent,
            size: 24,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'إعدادات الكابتن وتفضيلات القيادة',
                style: PieTypography.heading.copyWith(
                  fontWeight: FontWeight.w700,
                  color: PieColors.ink,
                  fontSize: isMobile ? 18 : 22,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'إدارة بيانات حسابك، تفضيلات الملاحة، بيئة الجهاز وتحديثات التطبيق',
                style: PieTypography.caption.copyWith(color: PieColors.inkSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProfileCard(AppServices services, AppUser? user, bool isMobile) {
    final emailDisplay = user?.email ?? 'driver@pie.eg';

    return PieCard(
      padding: const EdgeInsets.all(20),
      surfaceColor: PieColors.surface2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.person_pin_rounded, color: PieColors.driverAccent, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('بيانات الكابتن وملف الحساب', style: PieTypography.subheading),
                    const SizedBox(height: 2),
                    Text(
                      'تعديل اسمك المعروض على أوردرات الكاشير وبونات التوصيل',
                      style: PieTypography.caption.copyWith(color: PieColors.inkSecondary),
                    ),
                  ],
                ),
              ),
              PieBadge(
                label: _branchName,
                color: PieColors.driverAccent,
                backgroundColor: PieColors.driverSurface,
              ),
            ],
          ),
          const Divider(color: PieColors.border, height: 28),

          // Display Name Edit Row
          if (isMobile) ...[
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'اسم الكابتن',
                hintText: 'مثال: كابتن أحمد الشريف',
                prefixIcon: Icon(Icons.badge_outlined, color: PieColors.inkSecondary),
                border: OutlineInputBorder(borderRadius: PieRadius.borderMd),
                filled: true,
                fillColor: PieColors.surface3,
              ),
            ),
            const SizedBox(height: 12),
            PieButton.primary(
              onPressed: _isSavingProfile ? null : () => _saveProfile(services, user),
              label: _isSavingProfile ? 'جاري الحفظ...' : 'حفظ الاسم',
              icon: Icons.check_circle_outline,
              accentColor: PieColors.driverAccent,
              height: 44,
            ),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'اسم الكابتن',
                      hintText: 'مثال: كابتن أحمد الشريف',
                      prefixIcon: Icon(Icons.badge_outlined, color: PieColors.inkSecondary),
                      border: OutlineInputBorder(borderRadius: PieRadius.borderMd),
                      filled: true,
                      fillColor: PieColors.surface3,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                PieButton.primary(
                  onPressed: _isSavingProfile ? null : () => _saveProfile(services, user),
                  label: _isSavingProfile ? 'جاري الحفظ...' : 'حفظ الاسم',
                  icon: Icons.check_circle_outline,
                  accentColor: PieColors.driverAccent,
                  height: 48,
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),

          // Read-only email identifier
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: PieColors.surface3,
              borderRadius: PieRadius.borderMd,
              border: Border.all(color: PieColors.border),
            ),
            child: Row(
              children: [
                const Icon(Icons.alternate_email_rounded, size: 18, color: PieColors.inkSecondary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('البريد الإلكتروني / المعرّف:', style: PieTypography.caption),
                      const SizedBox(height: 2),
                      Directionality(
                        textDirection: TextDirection.ltr,
                        child: Text(
                          emailDisplay,
                          style: PieTypography.monoBody.copyWith(color: PieColors.ink),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Password Update Sub-card
          Text(
            'تحديث كلمة المرور',
            style: PieTypography.bodyStrong.copyWith(color: PieColors.ink),
          ),
          const SizedBox(height: 4),
          Text(
            'لأمان حسابك، استخدم كلمة مرور قوية مكونة من 6 خانات على الأقل.',
            style: PieTypography.caption.copyWith(color: PieColors.inkSecondary),
          ),
          const SizedBox(height: 12),

          if (isMobile) ...[
            TextField(
              controller: _newPasswordCtrl,
              obscureText: _obscureNewPassword,
              decoration: InputDecoration(
                labelText: 'كلمة المرور الجديدة',
                border: const OutlineInputBorder(borderRadius: PieRadius.borderMd),
                filled: true,
                fillColor: PieColors.surface3,
                suffixIcon: IconButton(
                  icon: Icon(_obscureNewPassword ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscureNewPassword = !_obscureNewPassword),
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _confirmPasswordCtrl,
              obscureText: _obscureConfirmPassword,
              decoration: InputDecoration(
                labelText: 'تأكيد كلمة المرور',
                border: const OutlineInputBorder(borderRadius: PieRadius.borderMd),
                filled: true,
                fillColor: PieColors.surface3,
                suffixIcon: IconButton(
                  icon: Icon(_obscureConfirmPassword ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                ),
              ),
            ),
            const SizedBox(height: 12),
            PieButton.secondary(
              onPressed: _isSavingProfile ? null : () => _saveProfile(services, user),
              label: 'تحديث كلمة المرور',
              icon: Icons.lock_reset_rounded,
              height: 44,
            ),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newPasswordCtrl,
                    obscureText: _obscureNewPassword,
                    decoration: InputDecoration(
                      labelText: 'كلمة المرور الجديدة',
                      border: const OutlineInputBorder(borderRadius: PieRadius.borderMd),
                      filled: true,
                      fillColor: PieColors.surface3,
                      suffixIcon: IconButton(
                        icon: Icon(_obscureNewPassword ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _obscureNewPassword = !_obscureNewPassword),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _confirmPasswordCtrl,
                    obscureText: _obscureConfirmPassword,
                    decoration: InputDecoration(
                      labelText: 'تأكيد كلمة المرور',
                      border: const OutlineInputBorder(borderRadius: PieRadius.borderMd),
                      filled: true,
                      fillColor: PieColors.surface3,
                      suffixIcon: IconButton(
                        icon: Icon(_obscureConfirmPassword ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                PieButton.secondary(
                  onPressed: _isSavingProfile ? null : () => _saveProfile(services, user),
                  label: 'تحديث كلمة المرور',
                  icon: Icons.lock_reset_rounded,
                  height: 48,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDriverPreferencesCard(AppServices services, bool isMobile) {
    if (_isLoadingPreferences) {
      return const PieCard(
        padding: EdgeInsets.all(24),
        surfaceColor: PieColors.surface2,
        child: Center(
          child: CircularProgressIndicator(strokeWidth: 2, color: PieColors.driverAccent),
        ),
      );
    }

    final vehicleOptions = [
      'موتوسيكل 🛵',
      'سكوتر 🛴',
      'دراجة 🚲',
      'سيارة 🚗',
    ];

    return PieCard(
      padding: const EdgeInsets.all(20),
      surfaceColor: PieColors.surface2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.two_wheeler_rounded, color: PieColors.driverAccent, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('تفضيلات القيادة والملاحة (خاصة بحسابك)', style: PieTypography.subheading),
                    const SizedBox(height: 2),
                    Text(
                      'إعدادات وسيلة النقل، أسلوب الملاحة والتنبيهات المخصصة لجهازك فقط',
                      style: PieTypography.caption.copyWith(color: PieColors.inkSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(color: PieColors.border, height: 28),

          // Vehicle Choice Chips
          Text(
            'مركبة التوصيل المعتمدة لديك:',
            style: PieTypography.bodyStrong.copyWith(color: PieColors.ink),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: vehicleOptions.map((v) {
              final isSelected = _driverSettings.vehicle == v;
              return ChoiceChip(
                label: Text(v, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                selected: isSelected,
                selectedColor: PieColors.driverSurface,
                backgroundColor: PieColors.surface3,
                side: BorderSide(
                  color: isSelected ? PieColors.driverAccent : PieColors.border,
                  width: isSelected ? 1.5 : 1.0,
                ),
                onSelected: (selected) {
                  if (selected) {
                    setState(() {
                      _driverSettings = _driverSettings.copyWith(vehicle: v);
                    });
                    PieSoundService.instance.click();
                  }
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 20),

          // Default Navigation Experience Choice
          Text(
            'وضع الملاحة الافتراضي عند فتح الأوردر:',
            style: PieTypography.bodyStrong.copyWith(color: PieColors.ink),
          ),
          const SizedBox(height: 8),
          _buildNavOption(
            value: 'cockpit',
            title: 'الملاحة المباشرة داخل التطبيق (3D Cockpit HUD)',
            subtitle: 'خريطة متجهة مدمجة، عداد سرعة وتوجيه مباشر لحظي بدون مغادرة التطبيق',
          ),
          const SizedBox(height: 6),
          _buildNavOption(
            value: 'google_maps',
            title: 'فتح خرائط Google Maps الخارجية',
            subtitle: 'توجيه فوري عبر تطبيق خرائط الهاتف المحمول',
          ),
          const Divider(color: PieColors.border, height: 24),

          // Audio & Toggles
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('المؤثرات والتنبيهات الصوتية', style: PieTypography.bodyStrong),
            subtitle: const Text('أصوات استلام الطلعات، تغيير المنعطفات، وتأكيد التسليم', style: PieTypography.caption),
            value: _driverSettings.soundEffects,
            activeThumbColor: PieColors.driverAccent,
            onChanged: (val) {
              setState(() => _driverSettings = _driverSettings.copyWith(soundEffects: val));
              PieSoundService.instance.enabled = val;
              if (val) PieSoundService.instance.click();
            },
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('الاهتزاز اللمسي (Haptic Feedback)', style: PieTypography.bodyStrong),
            subtitle: const Text('اهتزاز الجهاز عند استلام أوردر جديد أو الوصول للعنوان', style: PieTypography.caption),
            value: _driverSettings.hapticFeedback,
            activeThumbColor: PieColors.driverAccent,
            onChanged: (val) {
              setState(() => _driverSettings = _driverSettings.copyWith(hapticFeedback: val));
              if (val) HapticFeedback.mediumImpact();
            },
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('المنظور ثلاثي الأبعاد الافتراضي للخريطة (3D Tilt)', style: PieTypography.bodyStrong),
            subtitle: const Text('إمالة منظور الكاميرا للأمام بزاوية مريحة لتتبع الشوارع', style: PieTypography.caption),
            value: _driverSettings.mapPerspective3D,
            activeThumbColor: PieColors.driverAccent,
            onChanged: (val) {
              setState(() => _driverSettings = _driverSettings.copyWith(mapPerspective3D: val));
              PieSoundService.instance.click();
            },
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('تنبيه تجاوز السرعة المقررة', style: PieTypography.bodyStrong),
            subtitle: const Text('إظهار شارة حمراء على عداد السرعة عند تجاوز سرعة 50 كم/س', style: PieTypography.caption),
            value: _driverSettings.speedLimitWarning,
            activeThumbColor: PieColors.driverAccent,
            onChanged: (val) {
              setState(() => _driverSettings = _driverSettings.copyWith(speedLimitWarning: val));
              PieSoundService.instance.click();
            },
          ),
          const SizedBox(height: 16),

          // Save Preferences Button
          PieButton.primary(
            onPressed: _isSavingPreferences ? null : () => _savePreferences(services),
            label: _isSavingPreferences ? 'جاري الحفظ...' : 'حفظ تفضيلات القيادة',
            icon: Icons.save_rounded,
            accentColor: PieColors.driverAccent,
            height: 46,
          ),
        ],
      ),
    );
  }

  Widget _buildNavOption({
    required String value,
    required String title,
    required String subtitle,
  }) {
    final isSelected = _driverSettings.defaultNavigation == value;
    return InkWell(
      onTap: () {
        setState(() => _driverSettings = _driverSettings.copyWith(defaultNavigation: value));
        PieSoundService.instance.click();
      },
      borderRadius: PieRadius.borderMd,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? PieColors.driverSurface : PieColors.surface3,
          borderRadius: PieRadius.borderMd,
          border: Border.all(
            color: isSelected ? PieColors.driverAccent : PieColors.border,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
              color: isSelected ? PieColors.driverAccent : PieColors.inkMuted,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: PieTypography.bodyStrong),
                  const SizedBox(height: 2),
                  Text(subtitle, style: PieTypography.caption.copyWith(color: PieColors.inkSecondary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlatformAndUpdatesCard(AppServices services, bool isMobile) {
    final media = MediaQuery.of(context);
    final isDesktopPlatform = !isMobile;
    final platformTitle = isDesktopPlatform ? 'جهاز مكتبي / لوحي (Desktop/Tablet)' : 'هاتف محمول (Mobile Device)';
    final platformIcon = isDesktopPlatform ? Icons.laptop_chromebook_rounded : Icons.smartphone_rounded;
    final currentVer = AppVersion.number;

    return PieCard(
      padding: const EdgeInsets.all(20),
      surfaceColor: PieColors.surface2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.devices_rounded, color: PieColors.driverAccent, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('بيئة الجهاز وتحديثات التطبيق (PWA)', style: PieTypography.subheading),
                    const SizedBox(height: 2),
                    Text(
                      'معلومات النظام الحالي وفحص التحديثات البرمجية للكابتن',
                      style: PieTypography.caption.copyWith(color: PieColors.inkSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(color: PieColors.border, height: 28),

          // Environment Info Tiles
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: PieColors.surface3,
                    borderRadius: PieRadius.borderMd,
                    border: Border.all(color: PieColors.border),
                  ),
                  child: Row(
                    children: [
                      Icon(platformIcon, size: 22, color: PieColors.driverAccent),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(platformTitle, style: PieTypography.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 2),
                            Text(
                              'أبعاد الشاشة: ${media.size.width.toInt()} × ${media.size.height.toInt()} بكسل',
                              style: PieTypography.caption.copyWith(color: PieColors.inkSecondary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Version & PWA Card
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: PieColors.surface3,
              borderRadius: PieRadius.borderMd,
              border: Border.all(color: PieColors.border),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('إصدار النظام الحالي:', style: PieTypography.caption),
                      const SizedBox(height: 2),
                      Text(
                        'v$currentVer (بنية الإنتاج)',
                        style: PieTypography.monoBody.copyWith(
                          fontWeight: FontWeight.bold,
                          color: PieColors.ink,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                PieButton.secondary(
                  onPressed: _isCheckingUpdates ? null : () => _checkForUpdates(services),
                  label: _isCheckingUpdates ? 'جاري الفحص...' : 'فحص التحديثات',
                  icon: Icons.cloud_sync_outlined,
                  height: 38,
                ),
              ],
            ),
          ),

          if (_updateCheckMessage != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: PieColors.surfaceOverlay,
                borderRadius: PieRadius.borderMd,
                border: Border.all(color: PieColors.driverBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.info_outline_rounded, size: 18, color: PieColors.driverAccent),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _updateCheckMessage!,
                          style: PieTypography.caption.copyWith(color: PieColors.ink),
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
                          backgroundColor: PieColors.driverAccent,
                          foregroundColor: Colors.white,
                          shape: const RoundedRectangleBorder(borderRadius: PieRadius.borderSm),
                        ),
                        onPressed: () {
                          InAppUpdateDialog.show(
                            context,
                            manifest: _availableUpdateManifest!,
                            onComplete: () {
                              _checkForUpdates(services);
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),
          // PWA Cache Buster Row
          Row(
            children: [
              const Icon(Icons.cached_rounded, color: PieColors.driverAccent, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('تحديث كاش المتصفح (PWA Cache Buster)', style: PieTypography.bodyStrong),
                    const SizedBox(height: 2),
                    Text(
                      'يجلب أحدث نسخة مرفوعة على السيرفر ويمسح التخزين القديم فوراً',
                      style: PieTypography.caption.copyWith(color: PieColors.inkSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              PieButton.primary(
                onPressed: _isClearingCache ? null : _clearBrowserCache,
                label: _isClearingCache ? 'جاري التحديث...' : 'تحديث الآن',
                icon: Icons.refresh_rounded,
                accentColor: PieColors.driverAccent,
                height: 38,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

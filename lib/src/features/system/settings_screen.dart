import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/di/app_bootstrap.dart';
import '../../core/di/app_services.dart';
import '../../core/pwa/pwa_cache_service.dart';
import '../../core/sound/pie_sound_service.dart';
import '../../core/state/sync_monitor.dart';
import '../../core/theme/pie_colors.dart';
import '../../core/theme/pie_radius.dart';
import '../../core/theme/pie_typography.dart';
import '../../core/widgets/pie_button.dart';
import '../../core/widgets/pie_card.dart';
import '../../core/widgets/pie_toast.dart';
import '../../domain/models/app_role.dart';
import '../../domain/models/branch.dart';
import '../../domain/models/delivery_zone.dart';
import '../../domain/models/facility_settings.dart';
import '../../domain/services/network_esc_pos_adapter.dart';
import '../../domain/services/socket_printer/socket_printer_transport.dart';

/// Screen 26: Terminal Identity, Facility Settings, Tax & Service Rates, and Thermal Printer Preferences.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameArCtrl;
  late TextEditingController _nameEnCtrl;
  late TextEditingController _receiptNameCtrl;
  late TextEditingController _taxIdCtrl;
  late TextEditingController _commRegCtrl;
  late TextEditingController _vatRateCtrl;
  late TextEditingController _receiptFooterCtrl;
  late TextEditingController _printerIpCtrl;
  late TextEditingController _printerPortCtrl;

  String _printerCodepage = 'UTF-8';
  String _currency = 'ج.م';
  bool _networkPrintingEnabled = false;
  bool _isTestingPrinter = false;
  bool _autoAssignDelivery = true;
  bool _soundEffectsEnabled = true;
  bool _simulateOffline = false;
  bool _allowSignUp = true;
  bool _isClearingCache = false;
  String _activeBranchId = 'BR-01';
  List<BranchModel> _branches = [];
  List<DeliveryZone> _deliveryZones = [];
  bool _isLoadingZones = true;
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameArCtrl = TextEditingController();
    _nameEnCtrl = TextEditingController();
    _receiptNameCtrl = TextEditingController();
    _taxIdCtrl = TextEditingController();
    _commRegCtrl = TextEditingController();
    _vatRateCtrl = TextEditingController();
    _receiptFooterCtrl = TextEditingController();
    _printerIpCtrl = TextEditingController();
    _printerPortCtrl = TextEditingController();

    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSettings());
  }

  @override
  void dispose() {
    _nameArCtrl.dispose();
    _nameEnCtrl.dispose();
    _receiptNameCtrl.dispose();
    _taxIdCtrl.dispose();
    _commRegCtrl.dispose();
    _vatRateCtrl.dispose();
    _receiptFooterCtrl.dispose();
    _printerIpCtrl.dispose();
    _printerPortCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final services = AppScope.of(context);
    final facilityRepo = services.facility;
    final branchRepo = services.branches;

    FacilitySettings settings = const FacilitySettings();
    if (facilityRepo != null) {
      settings = await facilityRepo.load();
    }

    final branches = await branchRepo?.listBranches() ?? [];
    final activeBranch = await branchRepo?.activeBranch();

    if (mounted) {
      final isDemo = services.isDemo;
      setState(() {
        _nameArCtrl.text = settings.nameAr.isEmpty ? (isDemo ? 'مطعم الفطيرة الذهبية' : '') : settings.nameAr;
        _nameEnCtrl.text = settings.nameEn.isEmpty ? (isDemo ? 'The Golden Pie' : '') : settings.nameEn;
        _receiptNameCtrl.text = settings.receiptName.isEmpty ? (isDemo ? 'الفطيرة الذهبية - فرع المعادي' : '') : settings.receiptName;
        _taxIdCtrl.text = settings.taxId.isEmpty ? (isDemo ? '394-201-842' : '') : settings.taxId;
        _commRegCtrl.text = settings.commercialRegister.isEmpty ? (isDemo ? '108429' : '') : settings.commercialRegister;
        _vatRateCtrl.text = (settings.vatRate * 100).toStringAsFixed(0);
        _receiptFooterCtrl.text = settings.receiptFooter.isEmpty
            ? (isDemo ? 'شكراً لزيارتكم! الرقم الضريبي موثق.' : '')
            : settings.receiptFooter;
        _printerCodepage = settings.printerCodepage;
        _printerIpCtrl.text = settings.printerIp;
        _printerPortCtrl.text = settings.printerPort.toString();
        _networkPrintingEnabled = settings.networkPrintingEnabled;
        _currency = settings.currency;
        _autoAssignDelivery = settings.autoAssignDelivery;
        _soundEffectsEnabled = settings.soundEffectsEnabled;
        _simulateOffline = SyncMonitor.instance.isSimulatedOffline || settings.simulateOffline;
        _allowSignUp = settings.allowSignUp;
        _branches = branches;
        _activeBranchId = activeBranch?.id ?? settings.activeBranchId;
        _isLoading = false;
      });
    }

    try {
      final zones = await services.deliveries?.listZones() ?? [];
      if (mounted) {
        setState(() {
          _deliveryZones = zones;
          _isLoadingZones = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingZones = false);
    }

    if (services.firebaseReady) {
      try {
        final doc = await FirebaseFirestore.instance.collection('public_settings').doc('auth').get();
        if (doc.exists && doc.data() != null && doc.data()!.containsKey('allowSignUp')) {
          if (mounted) {
            setState(() {
              _allowSignUp = doc.data()!['allowSignUp'] as bool? ?? _allowSignUp;
            });
          }
        }
      } catch (_) {}
    }
  }

  Future<void> _refreshZones() async {
    final services = AppScope.of(context);
    final zones = await services.deliveries?.listZones() ?? [];
    if (mounted) {
      setState(() => _deliveryZones = zones);
    }
  }

  Future<void> _showAddOrEditZoneDialog([DeliveryZone? existing]) async {
    final isEditing = existing != null;
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final feeCtrl = TextEditingController(
      text: existing != null ? existing.fee.toStringAsFixed(0) : '20',
    );
    final timeCtrl = TextEditingController(
      text: existing != null ? existing.estimatedMinutes.toString() : '30',
    );
    final formKey = GlobalKey<FormState>();

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: PieColors.surfaceOverlay,
          shape: const RoundedRectangleBorder(
            borderRadius: PieRadius.borderLg,
            side: BorderSide(color: PieColors.border),
          ),
          title: Row(
            children: [
              Icon(
                isEditing ? Icons.edit_location_alt_outlined : Icons.add_location_alt_outlined,
                color: PieColors.cashierAccent,
              ),
              const SizedBox(width: 8),
              Text(
                isEditing ? 'تعديل منطقة ورسوم التوصيل' : 'إضافة منطقة توصيل جديدة',
                style: PieTypography.heading,
              ),
            ],
          ),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameCtrl,
                    style: PieTypography.body.copyWith(color: PieColors.textPrimary),
                    decoration: const InputDecoration(
                      labelText: 'اسم المنطقة / الحي',
                      hintText: 'مثال: حي الأربعين / المحطة',
                      prefixIcon: Icon(Icons.location_on_outlined),
                    ),
                    validator: (v) => v == null || v.trim().isEmpty ? 'يرجى إدخال اسم المنطقة' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: feeCtrl,
                    keyboardType: TextInputType.number,
                    style: PieTypography.body.copyWith(color: PieColors.textPrimary),
                    decoration: const InputDecoration(
                      labelText: 'رسوم التوصيل الثابتة (ج.م)',
                      hintText: 'مثال: 20',
                      prefixIcon: Icon(Icons.payments_outlined),
                      suffixText: 'ج.م',
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'يرجى إدخال الرسوم';
                      final numVal = double.tryParse(v.trim());
                      if (numVal == null || numVal < 0) return 'قيمة الرسوم غير صحيحة';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: timeCtrl,
                    keyboardType: TextInputType.number,
                    style: PieTypography.body.copyWith(color: PieColors.textPrimary),
                    decoration: const InputDecoration(
                      labelText: 'الوقت التقديري للوصول (بالدقائق)',
                      hintText: 'مثال: 30',
                      prefixIcon: Icon(Icons.timer_outlined),
                      suffixText: 'دقيقة',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              child: const Text('إلغاء'),
            ),
            PieButton.primary(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                final fee = double.tryParse(feeCtrl.text.trim()) ?? 20.0;
                final mins = int.tryParse(timeCtrl.text.trim()) ?? 30;
                final zone = DeliveryZone(
                  id: existing?.id ?? 'zone-${DateTime.now().millisecondsSinceEpoch}',
                  name: nameCtrl.text.trim(),
                  fee: fee,
                  estimatedMinutes: mins,
                  active: existing?.active ?? true,
                );
                final services = AppScope.of(context);
                await services.deliveries?.saveZone(zone);
                if (dialogCtx.mounted) {
                  Navigator.of(dialogCtx).pop(true);
                }
              },
              label: isEditing ? 'حفظ التعديل' : 'إضافة المنطقة',
              accentColor: PieColors.cashierAccent,
            ),
          ],
        ),
      ),
    );

    if (saved == true && mounted) {
      await _refreshZones();
      PieToast.show(
        context,
        isEditing ? 'تم تحديث منطقة التوصيل بنجاح' : 'تم إضافة منطقة التوصيل بنجاح',
        isSuccess: true,
      );
    }
  }

  Future<void> _deleteZone(DeliveryZone zone) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: PieColors.surfaceOverlay,
          shape: const RoundedRectangleBorder(
            borderRadius: PieRadius.borderLg,
            side: BorderSide(color: PieColors.border),
          ),
          title: const Text('حذف منطقة التوصيل', style: PieTypography.heading),
          content: Text(
            'هل أنت متأكد من حذف منطقة "${zone.name}" ورسومها (${PieTypography.formatEgp(zone.fee)})؟',
            style: PieTypography.body,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              child: const Text('إلغاء'),
            ),
            PieButton.primary(
              onPressed: () => Navigator.of(dialogCtx).pop(true),
              label: 'حذف المنطقة',
              accentColor: PieColors.stateError,
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && mounted) {
      final services = AppScope.of(context);
      await services.deliveries?.deleteZone(zone.id);
      await _refreshZones();
      PieToast.show(context, 'تم حذف منطقة "${zone.name}" بنجاح', isSuccess: true);
    }
  }

  Future<void> _toggleZoneActive(DeliveryZone zone, bool active) async {
    final updated = zone.copyWith(active: active);
    final services = AppScope.of(context);
    await services.deliveries?.saveZone(updated);
    await _refreshZones();
  }

  Future<void> _testPrinter() async {
    final ip = _printerIpCtrl.text.trim();
    final port = int.tryParse(_printerPortCtrl.text.trim()) ?? 9100;
    if (ip.isEmpty) {
      PieToast.show(
        context,
        'اكتب عنوان IP الخاص بالطابعة أولاً',
        isError: true,
      );
      return;
    }

    if (kIsWeb) {
      PieToast.show(
        context,
        'تنبيه الويب: الاتصال المباشر بمقابس الشبكة (TCP Port 9100) يتطلب تشغيل تطبيق سطح المكتب. على متصفح الويب، يتم إرسال الإيصالات تلقائياً عبر نافذة الطباعة الخاصة بالمتصفح.',
        isSuccess: true,
      );
      return;
    }

    setState(() => _isTestingPrinter = true);
    final services = AppScope.of(context);
    final adapter = services.print?.adapter;
    bool success = false;
    if (adapter is NetworkEscPosPrintAdapter) {
      success = await adapter.testPrinterConnection(ip, port);
    } else {
      success = await createSocketPrinterTransport().testConnection(ip, port);
    }

    if (mounted) {
      setState(() => _isTestingPrinter = false);
      PieToast.show(
        context,
        success
            ? 'تم الاتصال بالطابعة ($ip:$port) بنجاح!'
            : 'تعذّر الاتصال بالطابعة ($ip:$port). تأكد من توصيلها بالشبكة وتشغيلها.',
        isSuccess: success,
        isError: !success,
      );
    }
  }

  Future<void> _updateAllowSignUp(bool val) async {
    setState(() => _allowSignUp = val);
    PieSoundService.instance.pop();

    final services = AppScope.of(context);
    final facilityRepo = services.facility;
    if (facilityRepo != null) {
      final current = await facilityRepo.load();
      await facilityRepo.save(current.copyWith(allowSignUp: val));
    }

    if (services.firebaseReady) {
      try {
        await FirebaseFirestore.instance.collection('public_settings').doc('auth').set({
          'allowSignUp': val,
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedBy': services.auth.currentUser?.email ?? 'developer',
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint('Failed to sync auth settings: $e');
      }
    }
  }

  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    final services = AppScope.of(context);
    final facilityRepo = services.facility;
    final branchRepo = services.branches;

    final vat = (double.tryParse(_vatRateCtrl.text.trim()) ?? 14.0) / 100.0;
    const srv = 0.0;

    final selectedBranch = _branches.firstWhere(
      (b) => b.id == _activeBranchId,
      orElse: () => BranchModel(
        id: _activeBranchId.isNotEmpty ? _activeBranchId : 'main',
        name: 'الفرع الرئيسي',
        code: 'MAIN',
        city: 'القاهرة',
        timezone: 'Africa/Cairo',
        openedAt: DateTime.now(),
      ),
    );

    final updated = FacilitySettings(
      nameAr: _nameArCtrl.text.trim(),
      nameEn: _nameEnCtrl.text.trim(),
      receiptName: _receiptNameCtrl.text.trim(),
      taxId: _taxIdCtrl.text.trim(),
      commercialRegister: _commRegCtrl.text.trim(),
      vatRate: vat,
      serviceRate: srv,
      receiptFooter: _receiptFooterCtrl.text.trim(),
      printerCodepage: _printerCodepage,
      printerIp: _printerIpCtrl.text.trim(),
      printerPort: int.tryParse(_printerPortCtrl.text.trim()) ?? 9100,
      networkPrintingEnabled: _networkPrintingEnabled,
      currency: _currency,
      autoAssignDelivery: _autoAssignDelivery,
      soundEffectsEnabled: _soundEffectsEnabled,
      activeBranchId: _activeBranchId,
      activeBranchName: selectedBranch.name,
      simulateOffline: _simulateOffline,
      allowSignUp: _allowSignUp,
    );

    if (facilityRepo != null) {
      await facilityRepo.save(updated);
    }

    if (services.firebaseReady) {
      try {
        await FirebaseFirestore.instance.collection('public_settings').doc('auth').set({
          'allowSignUp': _allowSignUp,
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedBy': services.auth.currentUser?.email ?? 'developer',
        }, SetOptions(merge: true));
      } catch (_) {}
    }

    if (branchRepo != null) {
      await branchRepo.setActiveBranch(_activeBranchId);
    }

    PieSoundService.instance.enabled = _soundEffectsEnabled;
    SyncMonitor.instance.setSimulatedOffline(_simulateOffline);
    PieSoundService.instance.chime();

    if (mounted) {
      setState(() => _isSaving = false);
      PieToast.show(
        context,
        'تم حفظ وتحديث إعدادات المنشأة والفرع والتشغيل بنجاح.',
        isSuccess: true,
      );
    }
  }

  Future<void> _performRealReset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: PieColors.surface2,
          shape: RoundedRectangleBorder(borderRadius: PieRadius.borderLg),
          title: Row(
            children: const [
              Icon(Icons.cleaning_services_rounded, color: PieColors.stateWarning),
              SizedBox(width: 8),
              Text('تأكيد إعادة التهيئة وتحديث الكاش', style: PieTypography.heading),
            ],
          ),
          content: const Text(
            'سيتم حذف كافة البيانات التجريبية القديمة المخزنة محلياً، تفريغ كاش المتصفح بالكامل، وسحب أحدث نسخة من النظام مع إعادة التحميل الفوري.\n\nهل ترغب في الاستمرار؟',
            style: PieTypography.body,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء', style: TextStyle(color: PieColors.textSecondary)),
            ),
            PieButton(
              label: 'إعادة تهيئة وتحديث',
              icon: Icons.refresh_rounded,
              role: AppRole.developer,
              onPressed: () => Navigator.pop(ctx, true),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isClearingCache = true);
    PieSoundService.instance.click();

    PieToast.show(
      context,
      'جاري تنظيف قاعدة البيانات المحلية وحذف أية بيانات تجريبية وتحديث النظام...',
      isSuccess: true,
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

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final userRole = services.auth.currentUser?.role;
    final isAuthorized = userRole == AppRole.manager || userRole == AppRole.developer;

    if (!isAuthorized) {
      return Directionality(
        textDirection: TextDirection.rtl,
        child: Center(
          child: Container(
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(24),
            constraints: const BoxConstraints(maxWidth: 420),
            decoration: BoxDecoration(
              color: PieColors.surface2,
              borderRadius: PieRadius.borderLg,
              border: Border.all(color: PieColors.stateError.withValues(alpha: 0.4)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_person_outlined, color: PieColors.stateError, size: 48),
                const SizedBox(height: 16),
                const Text(
                  'غير مصرح بالدخول',
                  style: PieTypography.heading,
                ),
                const SizedBox(height: 8),
                Text(
                  'إعدادات المنشأة والنظام مخصصة فقط لمدير المطعم ومسؤول النظام.',
                  style: PieTypography.body.copyWith(color: PieColors.inkSecondary),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 600;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: PieColors.surface1,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'هوية الجهاز وإعدادات المنشأة',
                    style: (isDesktop ? PieTypography.h2 : PieTypography.heading).copyWith(color: PieColors.textPrimary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 10),
                PieButton(
                  label: _isSaving ? 'جاري الحفظ...' : 'حفظ الإعدادات',
                  icon: Icons.save_outlined,
                  role: AppRole.developer,
                  onPressed: _isSaving ? null : _saveSettings,
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: PieColors.roleSystem),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Terminal Identity Card
                      Text(
                        'هوية محطة التشغيل الحالية',
                        style: PieTypography.h3.copyWith(color: PieColors.textPrimary),
                      ),
                      const SizedBox(height: 8),
                      PieCard(
                        surface: PieColors.surface2,
                        role: AppRole.developer,
                        child: Column(
                          children: [
                            _buildInfoRow(
                              'معرف الجهاز (Node ID):',
                              services.config.projectId.isNotEmpty
                                  ? 'NODE-${services.config.projectId.substring(0, 8).toUpperCase()}'
                                  : 'NODE-TERMINAL-01',
                            ),
                            const Divider(height: 16, color: PieColors.borderSubtle),
                            _buildInfoRow(
                              'بيئة التشغيل:',
                              services.isDemo ? 'وضع تجريبي محلي (Offline-First Demo)' : 'إنتاج سحابي متصل',
                            ),
                            const Divider(height: 16, color: PieColors.borderSubtle),
                            _buildInfoRow(
                              'حالة التخزين المحلي:',
                              services.hasLocalStore ? 'مفعل ومحمي (Sembast Local Store)' : 'غير متوفر',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Facility Legal & Receipt Info
                      Text(
                        'بيانات المنشأة والفواتير الضريبية',
                        style: PieTypography.h3.copyWith(color: PieColors.textPrimary),
                      ),
                      const SizedBox(height: 8),
                      PieCard(
                        surface: PieColors.surface2,
                        child: Column(
                          children: [
                            TextFormField(
                              controller: _nameArCtrl,
                              style: PieTypography.body.copyWith(color: PieColors.textPrimary),
                              decoration: const InputDecoration(
                                labelText: 'اسم المنشأة التجاري (عربي)',
                                filled: true,
                                fillColor: PieColors.well,
                                border: OutlineInputBorder(),
                              ),
                              validator: (v) => v == null || v.trim().isEmpty ? 'مطلوب' : null,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _nameEnCtrl,
                              style: PieTypography.body.copyWith(color: PieColors.textPrimary),
                              decoration: const InputDecoration(
                                labelText: 'اسم المنشأة التجاري (إنجليزي)',
                                filled: true,
                                fillColor: PieColors.well,
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _receiptNameCtrl,
                              maxLength: 24,
                              style: PieTypography.body.copyWith(color: PieColors.textPrimary),
                              decoration: const InputDecoration(
                                labelText: 'ترويسة الفاتورة الحرارية (أقصى حد 24 حرف)',
                                filled: true,
                                fillColor: PieColors.well,
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (isDesktop)
                              Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: _taxIdCtrl,
                                      style: PieTypography.body.copyWith(color: PieColors.textPrimary),
                                      decoration: const InputDecoration(
                                        labelText: 'الرقم الضريبي',
                                        filled: true,
                                        fillColor: PieColors.well,
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: TextFormField(
                                      controller: _commRegCtrl,
                                      style: PieTypography.body.copyWith(color: PieColors.textPrimary),
                                      decoration: const InputDecoration(
                                        labelText: 'السجل التجاري',
                                        filled: true,
                                        fillColor: PieColors.well,
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            else
                              Column(
                                children: [
                                  TextFormField(
                                    controller: _taxIdCtrl,
                                    style: PieTypography.body.copyWith(color: PieColors.textPrimary),
                                    decoration: const InputDecoration(
                                      labelText: 'الرقم الضريبي',
                                      filled: true,
                                      fillColor: PieColors.well,
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  TextFormField(
                                    controller: _commRegCtrl,
                                    style: PieTypography.body.copyWith(color: PieColors.textPrimary),
                                    decoration: const InputDecoration(
                                      labelText: 'السجل التجاري',
                                      filled: true,
                                      fillColor: PieColors.well,
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Tax Configuration
                      Text(
                        'نسبة ضريبة القيمة المضافة الرسمية',
                        style: PieTypography.h3.copyWith(color: PieColors.textPrimary),
                      ),
                      const SizedBox(height: 8),
                      PieCard(
                        surface: PieColors.surface2,
                        child: TextFormField(
                          controller: _vatRateCtrl,
                          keyboardType: TextInputType.number,
                          style: PieTypography.body.copyWith(color: PieColors.textPrimary),
                          decoration: const InputDecoration(
                            labelText: 'ضريبة القيمة المضافة (%)',
                            suffixText: '%',
                            filled: true,
                            fillColor: PieColors.well,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Thermal Printer Preferences
                      Text(
                        'إعدادات الطابعة الحرارية وذيل الفاتورة',
                        style: PieTypography.h3.copyWith(color: PieColors.textPrimary),
                      ),
                      const SizedBox(height: 8),
                      PieCard(
                        surface: PieColors.surface2,
                        child: Column(
                          children: [
                            DropdownButtonFormField<String>(
                              initialValue: _printerCodepage,
                              dropdownColor: PieColors.surface3,
                              style: PieTypography.body.copyWith(color: PieColors.textPrimary),
                              decoration: const InputDecoration(
                                labelText: 'ترميز الخط العربي للطابعة (Codepage)',
                                filled: true,
                                fillColor: PieColors.well,
                                border: OutlineInputBorder(),
                              ),
                              items: const [
                                DropdownMenuItem(value: 'UTF-8', child: Text('UTF-8 (طابعات حديثة)')),
                                DropdownMenuItem(value: 'CP864', child: Text('CP864 (طابعات Epson/Star العربية)')),
                                DropdownMenuItem(value: 'Windows-1256', child: Text('Windows-1256 (طابعات قديمة)')),
                              ],
                              onChanged: (val) {
                                if (val != null) setState(() => _printerCodepage = val);
                              },
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _receiptFooterCtrl,
                              maxLines: 2,
                              style: PieTypography.body.copyWith(color: PieColors.textPrimary),
                              decoration: const InputDecoration(
                                labelText: 'رسالة ذيل الفاتورة المطبوعة',
                                filled: true,
                                fillColor: PieColors.well,
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Divider(color: PieColors.borderMuted),
                            const SizedBox(height: 8),
                            SwitchListTile(
                              value: _networkPrintingEnabled,
                              activeThumbColor: PieColors.roleCashier,
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                'تفعيل الطباعة المباشرة عبر الشبكة (LAN / Ethernet)',
                                style: PieTypography.bodyStrong.copyWith(color: PieColors.textPrimary),
                              ),
                              subtitle: Text(
                                'إرسال أوامر الطباعة وبونات المطبخ مباشرة إلى عنوان IP الطابعة الحرارية (Port 9100)',
                                style: PieTypography.caption.copyWith(color: PieColors.inkSecondary),
                              ),
                              onChanged: (val) => setState(() => _networkPrintingEnabled = val),
                            ),
                            if (_networkPrintingEnabled) ...[
                              if (kIsWeb) ...[
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: PieColors.surface2,
                                    borderRadius: PieRadius.borderMd,
                                    border: Border.all(color: PieColors.border),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.info_outline_rounded, size: 20, color: PieColors.cashierAccent),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          'تنبيه الويب: طابعات الشبكة المباشرة (Port 9100) تعمل على نسخة سطح المكتب (Windows / Linux / Android). على متصفح الويب، يتم إرسال الإيصالات بسلاسة عبر نافذة الطباعة الافتراضية.',
                                          style: PieTypography.caption.copyWith(color: PieColors.textPrimary),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(height: 12),
                              if (isDesktop)
                                Row(
                                  children: [
                                    Expanded(
                                      flex: 3,
                                      child: TextFormField(
                                        controller: _printerIpCtrl,
                                        style: PieTypography.body.copyWith(color: PieColors.textPrimary),
                                        decoration: const InputDecoration(
                                          labelText: 'عنوان IP الطابعة (مثال: 192.168.1.100)',
                                          filled: true,
                                          fillColor: PieColors.well,
                                          border: OutlineInputBorder(),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      flex: 1,
                                      child: TextFormField(
                                        controller: _printerPortCtrl,
                                        keyboardType: TextInputType.number,
                                        style: PieTypography.body.copyWith(color: PieColors.textPrimary),
                                        decoration: const InputDecoration(
                                          labelText: 'المنفذ (Port)',
                                          filled: true,
                                          fillColor: PieColors.well,
                                          border: OutlineInputBorder(),
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              else
                                Column(
                                  children: [
                                    TextFormField(
                                      controller: _printerIpCtrl,
                                      style: PieTypography.body.copyWith(color: PieColors.textPrimary),
                                      decoration: const InputDecoration(
                                        labelText: 'عنوان IP الطابعة (مثال: 192.168.1.100)',
                                        filled: true,
                                        fillColor: PieColors.well,
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    TextFormField(
                                      controller: _printerPortCtrl,
                                      keyboardType: TextInputType.number,
                                      style: PieTypography.body.copyWith(color: PieColors.textPrimary),
                                      decoration: const InputDecoration(
                                        labelText: 'المنفذ (Port)',
                                        filled: true,
                                        fillColor: PieColors.well,
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                  ],
                                ),
                              const SizedBox(height: 12),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: OutlinedButton.icon(
                                  icon: _isTestingPrinter
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        )
                                      : const Icon(Icons.print_outlined, size: 18),
                                  label: const Text('اختبار اتصال الطابعة'),
                                  onPressed: _isTestingPrinter ? null : _testPrinter,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Operational & Branch Settings ("branch is must", "auto dispatch in settings")
                      Text(
                        'إعدادات الفرع وإسناد التوصيل',
                        style: PieTypography.h3.copyWith(color: PieColors.textPrimary),
                      ),
                      const SizedBox(height: 8),
                      PieCard(
                        surface: PieColors.surface2,
                        child: Column(
                          children: [
                            if (_branches.isNotEmpty) ...[
                              DropdownButtonFormField<String>(
                                initialValue: _activeBranchId,
                                dropdownColor: PieColors.surface3,
                                style: PieTypography.body.copyWith(color: PieColors.textPrimary),
                                decoration: const InputDecoration(
                                  labelText: 'الفرع النشط الحالي (مطلوب)',
                                  filled: true,
                                  fillColor: PieColors.well,
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.storefront_outlined, color: PieColors.inkSecondary),
                                ),
                                items: _branches.map((b) {
                                  return DropdownMenuItem<String>(
                                    value: b.id,
                                    child: Text('${b.name} (${b.code}) - ${b.city}'),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null) setState(() => _activeBranchId = val);
                                },
                              ),
                              const SizedBox(height: 16),
                            ],
                            SwitchListTile.adaptive(
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                'الإسناد التلقائي لطلبات التوصيل',
                                style: PieTypography.bodyStrong.copyWith(color: PieColors.textPrimary),
                              ),
                              subtitle: Text(
                                _autoAssignDelivery
                                    ? 'مفعّل: يتم إسناد الأوردر تلقائياً لأقل طيار حمولة عند الدفع.'
                                    : 'متوقف: يظهر منبثق لاختيار وتعيين الطيار يدوياً من قائمة الطيارين المتاحين.',
                                style: PieTypography.caption.copyWith(color: PieColors.textSecondary),
                              ),
                              value: _autoAssignDelivery,
                              activeTrackColor: PieColors.roleCashier,
                              onChanged: (val) {
                                setState(() => _autoAssignDelivery = val);
                                PieSoundService.instance.pop();
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Manager-Exclusive Delivery Zones & Fees Card
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'مناطق ورسوم التوصيل (خاص بالإدارة)',
                                  style: PieTypography.h3.copyWith(color: PieColors.textPrimary),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'تحديد مناطق وأحياء التوصيل والرسوم الثابتة المعتمدة. تُحتسب تلقائياً للكاشير ولا يمكن تعديلها يدوياً.',
                                  style: PieTypography.caption.copyWith(color: PieColors.inkSecondary),
                                ),
                              ],
                            ),
                          ),
                          PieButton.secondary(
                            onPressed: () => _showAddOrEditZoneDialog(),
                            label: 'إضافة منطقة',
                            icon: Icons.add_location_alt_outlined,
                            height: 38,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      PieCard(
                        surface: PieColors.surface2,
                        child: _isLoadingZones
                            ? const Padding(
                                padding: EdgeInsets.all(24),
                                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                              )
                            : _deliveryZones.isEmpty
                                ? Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Center(
                                      child: Column(
                                        children: [
                                          const Icon(Icons.map_outlined, size: 36, color: PieColors.inkMuted),
                                          const SizedBox(height: 8),
                                          Text('لا توجد مناطق توصيل مسجلة', style: PieTypography.bodyStrong),
                                          const SizedBox(height: 4),
                                          Text('أضف مناطق التوصيل ليتم احتساب رسومها تلقائياً عند طلب العميل.', style: PieTypography.caption),
                                        ],
                                      ),
                                    ),
                                  )
                                : ListView.separated(
                                    shrinkWrap: true,
                                    physics: const NeverScrollableScrollPhysics(),
                                    itemCount: _deliveryZones.length,
                                    separatorBuilder: (_, __) => const Divider(color: PieColors.border, height: 1),
                                    itemBuilder: (context, index) {
                                      final zone = _deliveryZones[index];
                                      return Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 8),
                                        child: Row(
                                          children: [
                                            Container(
                                              width: 36,
                                              height: 36,
                                              decoration: BoxDecoration(
                                                color: zone.active
                                                    ? PieColors.cashierAccent.withValues(alpha: 0.15)
                                                    : PieColors.surface3,
                                                shape: BoxShape.circle,
                                              ),
                                              child: Icon(
                                                Icons.location_on_outlined,
                                                color: zone.active ? PieColors.cashierAccent : PieColors.inkMuted,
                                                size: 20,
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    zone.name,
                                                    style: PieTypography.bodyStrong.copyWith(
                                                      color: zone.active ? PieColors.textPrimary : PieColors.inkMuted,
                                                      decoration: zone.active ? null : TextDecoration.lineThrough,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    'وقت التوصيل التقديري: ${zone.estimatedMinutes} دقيقة',
                                                    style: PieTypography.caption.copyWith(color: PieColors.inkMuted),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: PieColors.surface3,
                                                borderRadius: PieRadius.borderSm,
                                                border: Border.all(color: PieColors.border),
                                              ),
                                              child: Text(
                                                '${PieTypography.formatEgp(zone.fee)} (ثابت)',
                                                style: PieTypography.monoBody.copyWith(
                                                  color: zone.active ? PieColors.cashierAccent : PieColors.inkMuted,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            Switch.adaptive(
                                              value: zone.active,
                                              activeTrackColor: PieColors.cashierAccent,
                                              onChanged: (val) => _toggleZoneActive(zone, val),
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.edit_outlined, size: 18),
                                              tooltip: 'تعديل',
                                              onPressed: () => _showAddOrEditZoneDialog(zone),
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.delete_outline, size: 18, color: PieColors.stateError),
                                              tooltip: 'حذف',
                                              onPressed: () => _deleteZone(zone),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                      ),
                      const SizedBox(height: 24),

                      // Sound Effects & Offline Testing
                      Text(
                        'المؤثرات الصوتية والشبكة',
                        style: PieTypography.h3.copyWith(color: PieColors.textPrimary),
                      ),
                      const SizedBox(height: 8),
                      PieCard(
                        surface: PieColors.surface2,
                        child: Column(
                          children: [
                            SwitchListTile.adaptive(
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                'المؤثرات الصوتية للتطبيق',
                                style: PieTypography.bodyStrong.copyWith(color: PieColors.textPrimary),
                              ),
                              subtitle: Text(
                                'تشغيل استجابة صوتية عند الضغط على الأزرار، إتمام الفواتير، والتنبيهات.',
                                style: PieTypography.caption.copyWith(color: PieColors.textSecondary),
                              ),
                              value: _soundEffectsEnabled,
                              activeTrackColor: PieColors.roleCashier,
                              onChanged: (val) {
                                setState(() => _soundEffectsEnabled = val);
                                PieSoundService.instance.enabled = val;
                                PieSoundService.instance.pop();
                              },
                            ),
                            const Divider(color: PieColors.border),
                            SwitchListTile.adaptive(
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                'محاكاة وضع أوفلاين (اختبار العمل بدون إنترنت)',
                                style: PieTypography.bodyStrong.copyWith(color: PieColors.textPrimary),
                              ),
                              subtitle: Text(
                                'يفصل الاتصال سحابياً لاختبار تخزين الأوردرات محلياً في صندوق الصادر.',
                                style: PieTypography.caption.copyWith(color: PieColors.textSecondary),
                              ),
                              value: _simulateOffline,
                              activeTrackColor: PieColors.stateOffline,
                              onChanged: (val) {
                                setState(() => _simulateOffline = val);
                                SyncMonitor.instance.setSimulatedOffline(val);
                                PieSoundService.instance.pop();
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Developer & Access Control Section
                      Text(
                        'صلاحيات الوصول وتسجيل الموظفين (تحكم المطور والمدير)',
                        style: PieTypography.h3.copyWith(color: PieColors.textPrimary),
                      ),
                      const SizedBox(height: 8),
                      PieCard(
                        surface: PieColors.surface2,
                        child: SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: Row(
                            children: [
                              Icon(
                                _allowSignUp ? Icons.person_add_rounded : Icons.person_off_rounded,
                                size: 20,
                                color: _allowSignUp ? PieColors.cashierAccent : PieColors.stateError,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'السماح بتسجيل موظفين جدد (Sign Up)',
                                style: PieTypography.bodyStrong.copyWith(color: PieColors.textPrimary),
                              ),
                            ],
                          ),
                          subtitle: Text(
                            _allowSignUp
                                ? 'التسجيل متاح حالياً: يمكن للموظفين إنشاء حسابات من شاشة تسجيل الدخول.'
                                : 'التسجيل مغلق: يتم إخفاء تبويب إنشاء الحساب ومنع تسجيل أي مستخدم جديد.',
                            style: PieTypography.caption.copyWith(
                              color: _allowSignUp ? PieColors.textSecondary : PieColors.stateError,
                            ),
                          ),
                          value: _allowSignUp,
                          activeTrackColor: PieColors.cashierAccent,
                          onChanged: (val) => _updateAllowSignUp(val),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Maintenance & Cache Purge Section
                      Text(
                        'صيانة النظام والذاكرة المؤقتة (Real Reset & Cache)',
                        style: PieTypography.h3.copyWith(color: PieColors.textPrimary),
                      ),
                      const SizedBox(height: 8),
                      PieCard(
                        surface: PieColors.surface2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.cleaning_services_outlined, color: PieColors.stateWarning, size: 24),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'تحديث الكاش وتفريغ البيانات التجريبية القديمة',
                                        style: PieTypography.bodyStrong.copyWith(color: PieColors.textPrimary),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'يقوم بحذف أية بيانات تجريبية أو أوردرات Mock قديمة من الذاكرة المحلية (Sembast/IndexedDB)، تفريغ Service Worker وكاش المتصفح، وسحب البيانات الحية الرسمية مع إعادة تحميل فورية.',
                                        style: PieTypography.caption.copyWith(color: PieColors.textSecondary),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: PieButton(
                                label: _isClearingCache
                                    ? 'جاري التنظيف وإعادة التحميل...'
                                    : 'إعادة تهيئة وتفريغ الكاش (Real Reset)',
                                icon: Icons.refresh_rounded,
                                role: AppRole.developer,
                                onPressed: _isClearingCache ? null : _performRealReset,
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
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(label, style: PieTypography.body.copyWith(color: PieColors.textSecondary)),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            value,
            style: PieTypography.body.copyWith(
              color: PieColors.textPrimary,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }
}

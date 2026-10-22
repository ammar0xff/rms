import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/di/app_services.dart';
import '../../core/sound/pie_sound_service.dart';
import '../../core/state/sync_monitor.dart';
import '../../core/theme/pie_colors.dart';
import '../../core/theme/pie_radius.dart';
import '../../core/theme/pie_typography.dart';
import '../../core/widgets/pie_button.dart';
import '../../core/widgets/pie_card.dart';
import '../../domain/models/app_role.dart';
import '../../domain/models/branch.dart';
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
  late TextEditingController _serviceRateCtrl;
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
  String _activeBranchId = 'BR-01';
  List<BranchModel> _branches = [];
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
    _serviceRateCtrl = TextEditingController();
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
    _serviceRateCtrl.dispose();
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
        _serviceRateCtrl.text = (settings.serviceRate * 100).toStringAsFixed(0);
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
        _branches = branches;
        _activeBranchId = activeBranch?.id ?? settings.activeBranchId;
        _isLoading = false;
      });
    }
  }

  Future<void> _testPrinter() async {
    final ip = _printerIpCtrl.text.trim();
    final port = int.tryParse(_printerPortCtrl.text.trim()) ?? 9100;
    if (ip.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: PieColors.stateError,
          content: Text('اكتب عنوان IP الخاص بالطابعة أولاً'),
        ),
      );
      return;
    }

    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: PieColors.surface2,
          content: Row(
            children: [
              const Icon(Icons.info_outline_rounded, color: PieColors.cashierAccent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'تنبيه الويب: الاتصال المباشر بمقابس الشبكة (TCP Port 9100) يتطلب تشغيل تطبيق سطح المكتب. على متصفح الويب، يتم إرسال الإيصالات تلقائياً عبر نافذة الطباعة الخاصة بالمتصفح.',
                  style: PieTypography.body.copyWith(color: PieColors.textPrimary),
                ),
              ),
            ],
          ),
          duration: const Duration(seconds: 5),
        ),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: success ? PieColors.stateSynced : PieColors.stateError,
          content: Text(success
              ? 'تم الاتصال بالطابعة ($ip:$port) بنجاح!'
              : 'تعذّر الاتصال بالطابعة ($ip:$port). تأكد من توصيلها بالشبكة وتشغيلها.'),
        ),
      );
    }
  }

  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    final services = AppScope.of(context);
    final facilityRepo = services.facility;
    final branchRepo = services.branches;

    final vat = (double.tryParse(_vatRateCtrl.text.trim()) ?? 14.0) / 100.0;
    final srv = (double.tryParse(_serviceRateCtrl.text.trim()) ?? 12.0) / 100.0;

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
    );

    if (facilityRepo != null) {
      await facilityRepo.save(updated);
    }

    if (branchRepo != null) {
      await branchRepo.setActiveBranch(_activeBranchId);
    }

    PieSoundService.instance.enabled = _soundEffectsEnabled;
    SyncMonitor.instance.setSimulatedOffline(_simulateOffline);
    PieSoundService.instance.chime();

    if (mounted) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: PieColors.stateSynced,
          content: Text('تم حفظ وتحديث إعدادات المنشأة والفرع والتشغيل بنجاح.'),
        ),
      );
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
                Text(
                  'هوية الجهاز وإعدادات المنشأة',
                  style: PieTypography.h2.copyWith(color: PieColors.textPrimary),
                ),
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
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Taxes and Charges
                      Text(
                        'نسب الضرائب ورسوم الخدمة الرسمية',
                        style: PieTypography.h3.copyWith(color: PieColors.textPrimary),
                      ),
                      const SizedBox(height: 8),
                      PieCard(
                        surface: PieColors.surface2,
                        child: Row(
                          children: [
                            Expanded(
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
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: _serviceRateCtrl,
                                keyboardType: TextInputType.number,
                                style: PieTypography.body.copyWith(color: PieColors.textPrimary),
                                decoration: const InputDecoration(
                                  labelText: 'رسوم خدمة الصالة (%)',
                                  suffixText: '%',
                                  filled: true,
                                  fillColor: PieColors.well,
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                          ],
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
        Text(label, style: PieTypography.body.copyWith(color: PieColors.textSecondary)),
        Text(
          value,
          style: PieTypography.body.copyWith(
            color: PieColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

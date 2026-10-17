import 'package:flutter/material.dart';

import '../../core/di/app_services.dart';
import '../../core/theme/pie_colors.dart';
import '../../core/theme/pie_typography.dart';
import '../../core/widgets/pie_button.dart';
import '../../core/widgets/pie_card.dart';
import '../../domain/models/app_role.dart';
import '../../domain/models/facility_settings.dart';

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

  String _printerCodepage = 'UTF-8';
  String _currency = 'ج.م';
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
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final facilityRepo = AppScope.of(context).facility;
    FacilitySettings settings = const FacilitySettings();
    if (facilityRepo != null) {
      settings = await facilityRepo.load();
    }

    if (mounted) {
      setState(() {
        _nameArCtrl.text = settings.nameAr.isEmpty ? 'مطعم الفطيرة الذهبية' : settings.nameAr;
        _nameEnCtrl.text = settings.nameEn.isEmpty ? 'The Golden Pie' : settings.nameEn;
        _receiptNameCtrl.text = settings.receiptName.isEmpty ? 'الفطيرة الذهبية - فرع المعادي' : settings.receiptName;
        _taxIdCtrl.text = settings.taxId.isEmpty ? '394-201-842' : settings.taxId;
        _commRegCtrl.text = settings.commercialRegister.isEmpty ? '108429' : settings.commercialRegister;
        _vatRateCtrl.text = (settings.vatRate * 100).toStringAsFixed(0);
        _serviceRateCtrl.text = (settings.serviceRate * 100).toStringAsFixed(0);
        _receiptFooterCtrl.text = settings.receiptFooter.isEmpty
            ? 'شكراً لزيارتكم! الرقم الضريبي موثق.'
            : settings.receiptFooter;
        _printerCodepage = settings.printerCodepage;
        _currency = settings.currency;
        _isLoading = false;
      });
    }
  }

  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    final facilityRepo = AppScope.of(context).facility;

    final vat = (double.tryParse(_vatRateCtrl.text.trim()) ?? 14.0) / 100.0;
    final srv = (double.tryParse(_serviceRateCtrl.text.trim()) ?? 12.0) / 100.0;

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
      currency: _currency,
    );

    if (facilityRepo != null) {
      await facilityRepo.save(updated);
    }

    if (mounted) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم حفظ وتحديث إعدادات المنشأة والطابعة محلياً بنجاح.'),
          backgroundColor: PieColors.stateSynced,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: PieColors.canvas,
        appBar: AppBar(
          backgroundColor: PieColors.surface1,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          title: Text(
            'هوية الجهاز وإعدادات المنشأة',
            style: PieTypography.h2.copyWith(color: PieColors.textPrimary),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: PieButton(
                label: _isSaving ? 'جاري الحفظ...' : 'حفظ الإعدادات',
                icon: Icons.save_outlined,
                role: AppRole.developer,
                onPressed: _isSaving ? null : _saveSettings,
              ),
            ),
          ],
        ),
        body: _isLoading
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
                              value: _printerCodepage,
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
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
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

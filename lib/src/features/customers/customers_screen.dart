import 'package:flutter/material.dart';

import '../../core/di/app_services.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/page.dart';
import '../../core/widgets/primitives.dart';
import '../../core/widgets/rms_table.dart';
import '../../core/widgets/status.dart';
import '../../core/widgets/surface_card.dart';
import '../../data/local/outbox/outbox_status.dart';
import '../../domain/models/customer.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  List<CustomerModel> _customers = const [];
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    _load();
  }

  Future<void> _load() async {
    final repo = AppScope.of(context).customers;
    if (repo == null) return;
    final customers = await repo.listCustomers();
    if (!mounted) return;
    setState(() => _customers = customers);
  }

  Future<void> _add() async {
    final repo = AppScope.of(context).customers;
    if (repo == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('التخزين المحلي غير متاح')),
      );
      return;
    }
    final draft = await showDialog<_CustomerDraft>(
      context: context,
      builder: (_) => const _CustomerDialog(),
    );
    if (draft == null) return;
    await repo.createCustomer(
      name: draft.name,
      phone: draft.phone,
      notes: draft.notes,
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return PageBody(
      children: [
        Row(
          children: [
            const Expanded(
              child: SectionHeader(
                title: 'العملاء',
                subtitle: 'دليل عناوين التوصيل · يُزامَن عند الاتصال',
              ),
            ),
            RmsButton(
              label: 'إضافة عميل',
              icon: Icons.person_add_alt,
              onPressed: _add,
            ),
          ],
        ),
        SurfaceCard(
          padding: EdgeInsets.zero,
          clip: true,
          child: _customers.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(20),
                  child: EmptyState(
                    icon: Icons.people_alt_outlined,
                    title: 'لا يوجد عملاء بعد',
                    message: 'أضف أول عميل بزر إضافة عميل.',
                  ),
                )
              : RmsTable(
                  columns: const [
                    RmsColumn('الاسم', flex: 3),
                    RmsColumn('الهاتف', flex: 3),
                    RmsColumn('الحالة', flex: 2, align: TextAlign.right),
                  ],
                  rows: [
                    for (final c in _customers)
                      [
                        Row(
                          children: [
                            Container(
                              width: 22,
                              height: 22,
                              decoration: const BoxDecoration(
                                  color: AppColors.hover,
                                  shape: BoxShape.circle),
                              alignment: Alignment.center,
                              child: Text(
                                c.name.isNotEmpty ? c.name.substring(0, 1) : '؟',
                                style: AppText.caption,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                                child: Text(c.name,
                                    style: AppText.tableCellPrimary,
                                    overflow: TextOverflow.ellipsis)),
                          ],
                        ),
                        Text(
                          c.phone.isEmpty ? '—' : c.phone,
                          style: AppText.tableCell,
                        ),
                        StatusText(
                          label: c.syncStatus == SyncStatus.synced
                              ? 'مُزامَن'
                              : 'محلي',
                          tone: c.syncStatus == SyncStatus.synced
                              ? StatusTone.positive
                              : StatusTone.warning,
                        ),
                      ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _CustomerDraft {
  const _CustomerDraft({
    required this.name,
    required this.phone,
    required this.notes,
  });

  final String name;
  final String phone;
  final String notes;
}

class _CustomerDialog extends StatefulWidget {
  const _CustomerDialog();

  @override
  State<_CustomerDialog> createState() => _CustomerDialogState();
}

class _CustomerDialogState extends State<_CustomerDialog> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _notes = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _submit() {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'الاسم مطلوب');
      return;
    }
    Navigator.of(context).pop(_CustomerDraft(
      name: _name.text,
      phone: _phone.text,
      notes: _notes.text,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text('عميل جديد'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _name,
                autofocus: true,
                textInputAction: TextInputAction.next,
                style: AppText.body.copyWith(color: AppColors.fgBright),
                decoration: const InputDecoration(
                  labelText: 'الاسم',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                style: AppText.body.copyWith(color: AppColors.fgBright),
                decoration: const InputDecoration(
                  labelText: 'الهاتف',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _notes,
                style: AppText.body.copyWith(color: AppColors.fgBright),
                decoration: const InputDecoration(
                  labelText: 'ملاحظات',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _submit(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!,
                    style: AppText.caption
                        .copyWith(color: AppColors.negative)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        RmsButton(
          label: 'إلغاء',
          variant: BtnVariant.ghost,
          onPressed: () => Navigator.of(context).pop(),
        ),
        RmsButton(
          label: 'حفظ',
          variant: BtnVariant.primary,
          icon: Icons.check,
          onPressed: _submit,
        ),
      ],
    );
  }
}

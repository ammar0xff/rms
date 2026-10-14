import 'package:flutter/material.dart';

import '../../core/di/app_services.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/page.dart';
import '../../core/widgets/primitives.dart';
import '../../core/widgets/rms_table.dart';
import '../../core/widgets/status.dart';
import '../../core/widgets/surface_card.dart';
import '../../domain/models/menu_item.dart';
import '../../data/mock/mock_data.dart';
import '../common/format.dart';

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  String _category = 'الكل';
  List<MenuItemModel> _items = const [];
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    _load();
  }

  Future<void> _load() async {
    final menu = AppScope.of(context).menu;
    List<MenuItemModel> loaded = const [];
    if (menu != null) {
      try {
        loaded = await menu.listMenu();
      } catch (_) {
        loaded = const [];
      }
    }
    if (!mounted) return;
    setState(() => _items = loaded.isEmpty ? _fallbackMenu : loaded);
  }

  /// Demo menu shown when the local store is unavailable.
  List<MenuItemModel> get _fallbackMenu => [
        for (final m in MockData.menu)
          MenuItemModel(
            id: m.name,
            name: m.name,
            category: m.category,
            price: m.price,
            station: m.station,
            available: m.available,
          ),
      ];

  Future<void> _createItem() async {
    final menu = AppScope.of(context).menu;
    final messenger = ScaffoldMessenger.of(context);
    if (menu == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('تعذر الحفظ: التخزين المحلي غير متاح')),
      );
      return;
    }
    final created = await showDialog<MenuItemModel>(
      context: context,
      builder: (_) => const _MenuItemDialog(),
    );
    if (created == null) return;
    await menu.upsertMenuItem(created);
    await _load();
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text('أُضيف الصنف «${created.name}» إلى القائمة المحلية')),
    );
  }

  Future<void> _toggleAvailability(MenuItemModel item) async {
    final menu = AppScope.of(context).menu;
    if (menu == null) return;
    await menu.upsertMenuItem(
      MenuItemModel(
        id: item.id,
        name: item.name,
        category: item.category,
        price: item.price,
        station: item.station,
        available: !item.available,
        lastModifiedAt: DateTime.now(),
        syncStatus: 'pending',
      ),
    );
    await _load();
  }

  List<String> get _categories =>
      ['الكل', ...{for (final m in _items) m.category}];

  @override
  Widget build(BuildContext context) {
    final items = _category == 'الكل'
        ? _items
        : _items.where((m) => m.category == _category).toList();

    return PageBody(
      children: [
        LayoutBuilder(
          builder: (context, c) {
            final actions = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Tag(label: 'الإعدادات v24', tone: StatusTone.neutral),
                const SizedBox(width: 8),
                const StatusText(label: 'آخر مزامنة', tone: StatusTone.positive),
                const SizedBox(width: 12),
                RmsButton(label: 'صنف جديد', icon: Icons.add, onPressed: _createItem),
              ],
            );
            if (c.maxWidth >= 600) {
              return Row(
                children: [
                  const Expanded(
                    child: SectionHeader(
                      title: 'القائمة والأسعار',
                      subtitle: 'نسخة مخزنة · الخادم هو المرجع، تُحدث عند المزامنة',
                    ),
                  ),
                  actions,
                ],
              );
            }
            // Phones: title on its own line, actions scroll sideways rather
            // than crushing the title to ~30px.
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionHeader(
                  title: 'القائمة والأسعار',
                  subtitle: 'نسخة مخزنة · الخادم هو المرجع، تُحدث عند المزامنة',
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: actions,
                ),
              ],
            );
          },
        ),
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final c in _categories)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _category = c),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: c == _category ? AppColors.brandSoft : Colors.transparent,
                        border: Border.all(
                          color: c == _category ? AppColors.brandLine : AppColors.borderStrong,
                        ),
                        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                      ),
                      child: Center(
                        child: Text(c,
                            style: AppText.caption.copyWith(
                              fontSize: 11,
                              color: c == _category ? AppColors.brand : AppColors.fgMuted,
                            )),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        SurfaceCard(
          padding: EdgeInsets.zero,
          clip: true,
          child: RmsTable(
            columns: const [
              RmsColumn('الصنف', flex: 4),
              RmsColumn('الفئة', flex: 2),
              RmsColumn('المحطة', flex: 2),
              RmsColumn('التوفر', flex: 2),
              RmsColumn('السعر', flex: 2, align: TextAlign.right),
            ],
            rows: [
              for (final m in items)
                [
                  Text(m.name, style: AppText.tableCellPrimary),
                  Text(m.category, style: AppText.tableCell),
                  Text(m.station, style: AppText.tableCell),
                  GestureDetector(
                    onTap: () => _toggleAvailability(m),
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: StatusText(
                        label: m.available ? 'متاح' : 'نفد المخزون',
                        tone: m.available ? StatusTone.positive : StatusTone.negative,
                      ),
                    ),
                  ),
                  Text(money(m.price),
                      style: AppText.tableCellPrimary.copyWith(fontWeight: FontWeight.w600)),
                ],
            ],
          ),
        ),
        SurfaceCard(
          level: SurfaceLevel.secondary,
          child: Row(
            children: const [
              Icon(Icons.cloud_sync_outlined, size: 16, color: AppColors.info),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'تُتطلب مسارات عمل مصرح بها عبر الإنترنت لتعديل القائمة. تستمر الأجهزة دون اتصال في البيع من آخر نسخة مزامنة؛ ويحذر التطبيق عندما يتجاوز عمر النسخة الحد الأقصى.',
                  style: AppText.body,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Collects a new menu item. Returns null when dismissed.
class _MenuItemDialog extends StatefulWidget {
  const _MenuItemDialog();

  @override
  State<_MenuItemDialog> createState() => _MenuItemDialogState();
}

class _MenuItemDialogState extends State<_MenuItemDialog> {
  final _name = TextEditingController();
  final _category = TextEditingController();
  final _price = TextEditingController();
  final _station = TextEditingController();
  bool _available = true;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _category.dispose();
    _price.dispose();
    _station.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    final category = _category.text.trim();
    final station = _station.text.trim();
    final price = double.tryParse(_price.text.trim());
    if (name.isEmpty || category.isEmpty || station.isEmpty || price == null || price <= 0) {
      setState(() => _error = 'أكمل جميع الحقول بسعر صالح أكبر من صفر');
      return;
    }
    Navigator.of(context).pop(
      MenuItemModel(
        id: name,
        name: name,
        category: category,
        price: price,
        station: station,
        available: _available,
        lastModifiedAt: DateTime.now(),
        syncStatus: 'pending',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text('صنف جديد'),
      content: SizedBox(
        width: double.maxFinite,
        // Scrolls when the keyboard takes half the screen.
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
            _Field(controller: _name, label: 'اسم الصنف', autofocus: true),
            const SizedBox(height: 10),
            _Field(controller: _category, label: 'الفئة'),
            const SizedBox(height: 10),
            _Field(controller: _price, label: 'السعر', keyboardType: TextInputType.number),
            const SizedBox(height: 10),
            _Field(controller: _station, label: 'محطة التحضير'),
            const SizedBox(height: 12),
            Row(
              children: [
                const Expanded(child: Text('متاح للبيع', style: AppText.bodyStrong)),
                Switch(
                  value: _available,
                  onChanged: (v) => setState(() => _available = v),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: AppText.caption.copyWith(color: AppColors.negative)),
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

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    this.autofocus = false,
    this.keyboardType,
  });

  final TextEditingController controller;
  final String label;
  final bool autofocus;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      keyboardType: keyboardType,
      style: AppText.body.copyWith(color: AppColors.fgBright),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: AppText.caption,
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        ),
      ),
    );
  }
}

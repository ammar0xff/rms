import 'package:flutter/material.dart';

import '../../core/di/app_services.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/page.dart';
import '../../core/widgets/primitives.dart';
import '../../core/widgets/blocks.dart';
import '../../core/widgets/status.dart';
import '../../core/widgets/surface_card.dart';
import '../../domain/models/menu_item.dart';
import '../../domain/models/permissions.dart';
import '../../data/services/permission_service.dart';
import '../common/format.dart';

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  String _query = '';
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
    setState(() => _items = loaded);
  }

  /// Demo menu shown when the local store is unavailable.

  Future<void> _deny(String what) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('صلاحية $what مش متاحة لدورك')),
    );
  }

  Future<bool> _allowed() async =>
      userCan(AppScope.of(context), Permissions.menuEdit);

  Future<void> _createItem() async {
    if (!await _allowed()) {
      await _deny('تعديل القائمة');
      return;
    }
    final menu = AppScope.of(context).menu;
    final messenger = ScaffoldMessenger.of(context);
    if (menu == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('الحفظ فشل: التخزين على الجهاز مش متاح')),
      );
      return;
    }
    final created = await showDialog<MenuItemModel>(
      context: context,
      builder: (_) => const MenuItemDialog(),
    );
    if (created == null) return;
    await menu.upsertMenuItem(created);
    await _load();
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text('اتضاف الصنف «${created.name}» للقائمة على الجهاز')),
    );
  }

  Future<void> _toggleAvailability(MenuItemModel item) async {
    if (!await _allowed()) {
      await _deny('تعديل القائمة');
      return;
    }
    final menu = AppScope.of(context).menu;
    if (menu == null) return;
    try {
      await menu.upsertMenuItem(
        item.copyWith(
          available: !item.available,
          lastModifiedAt: DateTime.now(),
          syncStatus: 'pending',
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('التوفر ما اتغيرش، جرّب تاني')),
      );
      return;
    }
    await _load();
  }

  List<String> get _stations =>
      [...{for (final m in _items) m.station}];

  @override
  Widget build(BuildContext context) {
    final q = _query.trim();
    final items = q.isEmpty
        ? _items
        : _items.where((m) => m.name.contains(q)).toList();

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
                      subtitle: 'نسخة متخزنة · السيرفر هو المرجع، وبتتحدث مع المزامنة',
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
                  subtitle: 'نسخة متخزنة · السيرفر هو المرجع، وبتتحدث مع المزامنة',
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
        ListToolbar(
          hint: 'دوّر في القائمة…',
          onQuery: (v) => setState(() => _query = v),
        ),
        if (items.isEmpty)
          const SurfaceCard(
            child: EmptyState(
              icon: Icons.restaurant_menu_outlined,
              title: 'مفيش أصناف',
              message: 'ضيف أول صنف من زرار صنف جديد.',
            ),
          )
        else
          for (final station in _stations)
            if (items.any((m) => m.station == station))
              _StationGroup(
                station: station,
                items: items.where((m) => m.station == station).toList(),
                onToggle: _toggleAvailability,
              ),
        SurfaceCard(
          level: SurfaceLevel.secondary,
          child: Row(
            children: const [
              Icon(Icons.cloud_sync_outlined, size: 16, color: AppColors.info),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'تعديل القائمة محتاج نت وصلاحية. من غير نت البيع شغال من آخر نسخة متزامنة، والتطبيق بينبهك لو النسخة قدمت.',
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
/// One station's items: header with counts, cards with big availability
/// toggles. Stations, not a five-column table — and a greasy thumb
/// needs the whole row, not a 60px status cell.
class _StationGroup extends StatelessWidget {
  const _StationGroup({
    required this.station,
    required this.items,
    required this.onToggle,
  });

  final String station;
  final List<MenuItemModel> items;
  final ValueChanged<MenuItemModel> onToggle;

  @override
  Widget build(BuildContext context) {
    final out = items.where((m) => !m.available).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(station, style: AppText.h2),
            ),
            Tag(
              label: out > 0
                  ? '${items.length} صنف · $out نفد'
                  : '${items.length} صنف',
              tone: out > 0 ? StatusTone.warning : StatusTone.neutral,
            ),
          ],
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, c) => GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: c.maxWidth >= 700 ? 2 : 1,
              mainAxisExtent: 152,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: items.length,
            itemBuilder: (context, i) => _MenuItemCard(
              item: items[i],
              onToggle: () => onToggle(items[i]),
            ),
          ),
        ),
      ],
    );
  }
}

class _MenuItemCard extends StatelessWidget {
  const _MenuItemCard({required this.item, required this.onToggle});

  final MenuItemModel item;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: item.available ? 1 : 0.55,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(
            color: item.available
                ? AppColors.borderStrong
                : AppColors.negative.withValues(alpha: 0.4),
          ),
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.bodyStrong,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${item.category} · ${money(item.price)}',
                          overflow: TextOverflow.ellipsis,
                          style: AppText.caption,
                        ),
                      ],
                    ),
                  ),
                  if (!item.available) ...[
                    const SizedBox(width: 6),
                    const Tag(label: 'نفد', tone: StatusTone.negative),
                  ],
                ],
              ),
            ),
            // The whole row toggles: a 48px switch alone is a small target
            // with wet hands.
            GestureDetector(
              onTap: onToggle,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.available ? 'متاح للبيع' : 'موقوف مؤقتًا',
                        style: AppText.tableCellPrimary.copyWith(
                          color: item.available
                              ? AppColors.positive
                              : AppColors.negative,
                        ),
                      ),
                    ),
                    Switch.adaptive(
                      value: item.available,
                      activeColor: AppColors.positive,
                      onChanged: (_) => onToggle(),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MenuItemDialog extends StatefulWidget {
  const MenuItemDialog();

  @override
  State<MenuItemDialog> createState() => _MenuItemDialogState();
}

/// One modifier group under construction in the item dialog.
class _GroupDraft {
  _GroupDraft({required this.name});

  String name;
  bool required = false;
  bool multi = true;
  final List<ModifierOption> options = [];
}

class _MenuItemDialogState extends State<MenuItemDialog> {
  final _name = TextEditingController();
  final _category = TextEditingController();
  final _price = TextEditingController();
  final _station = TextEditingController();
  final _groupName = TextEditingController();
  final _optionName = TextEditingController();
  final _optionPrice = TextEditingController();
  bool _available = true;
  String? _error;
  final List<_GroupDraft> _groups = [];
  String? _editingGroup;

  @override
  void dispose() {
    _name.dispose();
    _category.dispose();
    _price.dispose();
    _station.dispose();
    _groupName.dispose();
    _optionName.dispose();
    _optionPrice.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    final category = _category.text.trim();
    final station = _station.text.trim();
    final price = double.tryParse(_price.text.trim());
    if (name.isEmpty || category.isEmpty || station.isEmpty || price == null || price <= 0) {
      setState(() => _error = 'كمّل كل الحقول بسعر سليم أكبر من صفر');
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
        modifierGroups: [
          for (final g in _groups)
            ModifierGroup(
              id: g.name,
              name: g.name,
              required: g.required,
              multi: g.multi,
              options: List.of(g.options),
            ),
        ],
      ),
    );
  }

  Widget _groupEditor(_GroupDraft group) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                  child: Text('إلزامي', style: AppText.tableCell)),
              Switch.adaptive(
                value: group.required,
                onChanged: (v) => setState(() => group.required = v),
              ),
            ],
          ),
          Row(
            children: [
              const Expanded(
                  child:
                      Text('اختيارات متعددة', style: AppText.tableCell)),
              Switch.adaptive(
                value: group.multi,
                onChanged: (v) => setState(() => group.multi = v),
              ),
            ],
          ),
          for (final option in group.options)
            Row(
              children: [
                Expanded(
                  child: Text(
                    option.deltaPrice > 0
                        ? '${option.name} (+${money(option.deltaPrice)})'
                        : option.name,
                    style: AppText.tableCellPrimary,
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(
                      () => group.options.remove(option)),
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(Icons.delete_outline,
                        size: 16, color: AppColors.negative),
                  ),
                ),
              ],
            ),
          Row(
            children: [
              Expanded(
                child: _Field(
                  controller: _optionName,
                  label: 'اختيار جديد',
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 76,
                child: _Field(
                  controller: _optionPrice,
                  label: 'سعر +',
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 6),
              RmsButton(
                label: 'ضيف',
                onPressed: _optionName.text.trim().isEmpty
                    ? null
                    : () => setState(() {
                          group.options.add(ModifierOption(
                            id:
                                '${group.name}:${_optionName.text.trim()}',
                            name: _optionName.text.trim(),
                            deltaPrice: double.tryParse(
                                    _optionPrice.text.trim()) ??
                                0,
                          ));
                          _optionName.clear();
                          _optionPrice.clear();
                        }),
              ),
            ],
          ),
        ],
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
            const Text('مجموعات التخصيص', style: AppText.bodyStrong),
            const SizedBox(height: 6),
            for (final g in _groups) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${g.name} (${g.options.length})${g.required ? ' · إلزامي' : ''}',
                      style: AppText.tableCellPrimary,
                    ),
                  ),
                  GestureDetector(
                    onTap: () =>
                        setState(() => _editingGroup = g.name),
                    child: const Padding(
                      padding: EdgeInsets.all(6),
                      child: Icon(Icons.edit_outlined, size: 16),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => setState(() {
                      _groups.remove(g);
                      if (_editingGroup == g.name) _editingGroup = null;
                    }),
                    child: const Padding(
                      padding: EdgeInsets.all(6),
                      child: Icon(Icons.delete_outline,
                          size: 16, color: AppColors.negative),
                    ),
                  ),
                ],
              ),
              if (_editingGroup == g.name) _groupEditor(g),
            ],
            Row(
              children: [
                Expanded(
                  child: _Field(
                    controller: _groupName,
                    label: 'اسم مجموعة جديدة',
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                RmsButton(
                  label: 'ضيف مجموعة',
                  onPressed: _groupName.text.trim().isEmpty
                      ? null
                      : () => setState(() {
                            _groups.add(_GroupDraft(
                                name: _groupName.text.trim()));
                            _groupName.clear();
                          }),
                ),
              ],
            ),
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
          label: 'احفظ',
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
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final bool autofocus;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      keyboardType: keyboardType,
      onChanged: onChanged,
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

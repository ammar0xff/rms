import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/page.dart';
import '../../core/widgets/primitives.dart';
import '../../core/widgets/rms_table.dart';
import '../../core/widgets/status.dart';
import '../../core/widgets/surface_card.dart';
import '../common/format.dart';
import '../../core/di/app_services.dart';
import '../../domain/models/menu_item.dart';

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  String _category = 'الكل';
  List<MenuItemModel> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final menu = AppScope.of(context).menu;
    if (menu == null) return;
    final items = await menu.listMenu();
    if (!mounted) return;
    setState(() => _items = items);
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
        Row(
          children: [
            const SectionHeader(
              title: 'القائمة والأسعار',
              subtitle: 'نسخة مخزنة · الخادم هو المرجع، تُحدث عند المزامنة',
            ),
            const Spacer(),
            const Tag(label: 'الإعدادات v24', tone: StatusTone.neutral),
            const SizedBox(width: 8),
            const StatusText(label: 'آخر مزامنة', tone: StatusTone.positive),
            const SizedBox(width: 12),
            RmsButton(label: 'صنف جديد', icon: Icons.add, onPressed: () {}),
          ],
        ),
        SizedBox(
          height: 30,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final c in _categories)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _category = c),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
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
                  StatusText(
                    label: m.available ? 'متاح' : 'نفد المخزون',
                    tone: m.available ? StatusTone.positive : StatusTone.negative,
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

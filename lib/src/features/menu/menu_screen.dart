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
import '../../data/mock/mock_data.dart';
import '../common/format.dart';

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  String _category = 'All';

  List<String> get _categories =>
      ['All', ...{for (final m in MockData.menu) m.category}];

  @override
  Widget build(BuildContext context) {
    final items = _category == 'All'
        ? MockData.menu
        : MockData.menu.where((m) => m.category == _category).toList();

    return PageBody(
      children: [
        Row(
          children: [
            const SectionHeader(
              title: 'Menu & pricing',
              subtitle: 'Cached snapshot · server-authoritative, refreshed on sync',
            ),
            const Spacer(),
            const Tag(label: 'CONFIG v24', tone: StatusTone.neutral),
            const SizedBox(width: 8),
            const StatusText(label: 'Synced 2m ago', tone: StatusTone.positive),
            const SizedBox(width: 12),
            RmsButton(label: 'New item', icon: Icons.add, onPressed: () {}),
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
              RmsColumn('Item', flex: 4),
              RmsColumn('Category', flex: 2),
              RmsColumn('Station', flex: 2),
              RmsColumn('Availability', flex: 2),
              RmsColumn('Price', flex: 2, align: TextAlign.right),
            ],
            rows: [
              for (final m in items)
                [
                  Text(m.name, style: AppText.tableCellPrimary),
                  Text(m.category, style: AppText.tableCell),
                  Text(m.station, style: AppText.tableCell),
                  StatusText(
                    label: m.available ? 'Available' : 'Sold out',
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
                  'Menu changes require an authorized online workflow. Offline devices keep selling from the last synchronized snapshot; the app warns when the cache exceeds its maximum age.',
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

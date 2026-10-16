import 'package:flutter/material.dart';

import '../../core/di/app_services.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/blocks.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/page.dart';
import '../../core/widgets/primitives.dart';
import '../../core/widgets/status.dart';
import '../../core/widgets/surface_card.dart';
import '../../domain/models/dining_table.dart';

/// Dine-in floor: seat parties, call the bill, free tables.
///
/// Status-first cards grouped by zone; the running tab lives on the order,
/// so this screen never touches money — only who sits where and whether
/// they asked for the check.
class TablesScreen extends StatefulWidget {
  const TablesScreen({super.key});

  @override
  State<TablesScreen> createState() => _TablesScreenState();
}

class _TablesScreenState extends State<TablesScreen> {
  List<DiningTable> _tables = const [];
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    _load();
  }

  Future<void> _load() async {
    final repo = AppScope.of(context).tables;
    if (repo == null) return;
    final tables = await repo.listTables();
    if (!mounted) return;
    setState(() => _tables = tables);
  }

  Future<void> _seat(DiningTable table) async {
    final repo = AppScope.of(context).tables;
    if (repo == null) return;
    final input = await showDialog<_SeatInput>(
      context: context,
      builder: (_) => _SeatSheet(table: table),
    );
    if (input == null) return;
    try {
      await repo.seatTable(
        tableId: table.id,
        partySize: input.partySize,
        steward: input.steward,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذّر التسكين — جرّب تاني')),
      );
      return;
    }
    await _load();
  }

  Future<void> _bill(DiningTable table) async {
    final repo = AppScope.of(context).tables;
    if (repo == null) return;
    await repo.requestBill(table.id);
    await _load();
  }

  Future<void> _clear(DiningTable table) async {
    final repo = AppScope.of(context).tables;
    if (repo == null) return;
    await repo.clearTable(table.id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final zones = <String>[];
    for (final t in _tables) {
      if (!zones.contains(t.zone)) zones.add(t.zone);
    }
    final occupied = _tables
        .where((t) => t.status != TableStatus.vacant)
        .length;
    return PageBody(
      children: [
        SectionHeader(
          title: 'خريطة الصالة والطاولات',
          subtitle: _tables.isEmpty
              ? 'مفيش طاولات متعرفة لسه.'
              : '$occupied من ${_tables.length} مشغول',
        ),
        if (zones.isEmpty)
          const SurfaceCard(
            child: Text(
              'عرّف الطاولات من إعدادات الفروع عشان الخريطة تشتغل.',
              style: AppText.caption,
            ),
          )
        else
          for (final zone in zones) ...[
            Text(zone, style: AppText.h2),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, c) => GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: c.maxWidth >= 700 ? 3 : 2,
                  mainAxisExtent: 148,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount:
                    _tables.where((t) => t.zone == zone).length,
                itemBuilder: (context, i) {
                  final table = _tables
                      .where((t) => t.zone == zone)
                      .toList()[i];
                  return _TableCard(
                    table: table,
                    onSeat: () => _seat(table),
                    onBill: () => _bill(table),
                    onClear: () => _clear(table),
                  );
                },
              ),
            ),
          ],
      ],
    );
  }
}

class _TableCard extends StatelessWidget {
  const _TableCard({
    required this.table,
    required this.onSeat,
    required this.onBill,
    required this.onClear,
  });

  final DiningTable table;
  final VoidCallback onSeat;
  final VoidCallback onBill;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final tone = switch (table.status) {
      TableStatus.vacant => StatusTone.positive,
      TableStatus.occupied => StatusTone.warning,
      TableStatus.billRequested => StatusTone.info,
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(
          color: table.status == TableStatus.vacant
              ? AppColors.borderStrong
              : tone == StatusTone.warning
                  ? AppColors.warning.withValues(alpha: 0.5)
                  : AppColors.info.withValues(alpha: 0.5),
        ),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              StatusDot(tone: tone),
              const SizedBox(width: 6),
              Expanded(
                child: Text(table.code, style: AppText.h2),
              ),
              Text(table.status.label, style: AppText.caption),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            table.status == TableStatus.vacant
                ? 'سعة ${table.capacity} أفراد'
                : '${table.partySize} أفراد'
                    '${table.steward.isEmpty ? '' : ' · ${table.steward}'}',
            style: AppText.caption,
            overflow: TextOverflow.ellipsis,
          ),
          const Spacer(),
          switch (table.status) {
            TableStatus.vacant => RmsButton(
                label: 'تسكين',
                dense: true,
                onPressed: onSeat,
              ),
            TableStatus.occupied => RmsButton(
                label: 'مطلوب الشيك',
                dense: true,
                onPressed: onBill,
              ),
            TableStatus.billRequested => RmsButton(
                label: 'تحرير بعد الدفع',
                dense: true,
                variant: BtnVariant.secondary,
                onPressed: onClear,
              ),
          },
        ],
      ),
    );
  }
}

class _SeatInput {
  _SeatInput({required this.partySize, required this.steward});

  final int partySize;
  final String steward;
}

class _SeatSheet extends StatefulWidget {
  const _SeatSheet({required this.table});

  final DiningTable table;

  @override
  State<_SeatSheet> createState() => _SeatSheetState();
}

class _SeatSheetState extends State<_SeatSheet> {
  int _party = 2;
  final _steward = TextEditingController();

  @override
  void dispose() {
    _steward.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DialogShell(
      title: 'تسكين ${widget.table.code}',
      subtitle: 'سعة ${widget.table.capacity} أفراد.',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Expanded(
                  child: Text('عدد الأفراد', style: AppText.bodyStrong)),
              _DenomLikeButton(
                  icon: Icons.remove,
                  onTap: () =>
                      setState(() => _party = (_party - 1).clamp(1, 99))),
              SizedBox(
                width: 40,
                child: Text('$_party',
                    textAlign: TextAlign.center,
                    style: AppText.h1.copyWith(fontSize: 20)),
              ),
              _DenomLikeButton(
                  icon: Icons.add,
                  onTap: () =>
                      setState(() => _party = (_party + 1).clamp(1, 99))),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _steward,
            decoration: const InputDecoration(
              labelText: 'المضيف (اختياري)',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        RmsButton(
          label: 'إلغاء',
          variant: BtnVariant.ghost,
          onPressed: () => Navigator.of(context).pop(),
        ),
        if (_party > widget.table.capacity)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('فوق سعة الطاولة — هيتسجّل كده.',
                style: AppText.caption),
          ),
        RmsButton(
          label: 'سكّن الطاولة',
          onPressed: () => Navigator.of(context).pop(
            _SeatInput(
                partySize: _party, steward: _steward.text.trim()),
          ),
        ),
      ],
    );
  }
}

class _DenomLikeButton extends StatelessWidget {
  const _DenomLikeButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.borderStrong),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(icon, size: 18, color: AppColors.fgSecondary),
      ),
    );
  }
}

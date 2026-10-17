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
import '../common/format.dart';

/// Dine-in floor: seat parties, call the bill, free tables.
///
/// Status-first cards grouped by zone; the running tab lives on the order,
/// so the model keeps no duplicated totals — only who sits where and whether
/// they asked for the check.
class TablesScreen extends StatefulWidget {
  const TablesScreen({super.key});

  @override
  State<TablesScreen> createState() => _TablesScreenState();
}

class _TablesScreenState extends State<TablesScreen> {
  List<DiningTable> _tables = const [];
  bool _loaded = false;

  /// Null means every table. Otherwise the one status the pills are filtering
  /// to, so the counts on each pill and the grid below can never disagree.
  TableStatus? _filter;

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

  /// The tables of one zone that survive the status filter. A zone with
  /// nothing left in it renders as no band at all, rather than an empty one.
  List<DiningTable> _visibleIn(String zone) => _tables
      .where((t) => t.zone == zone && (_filter == null || t.status == _filter))
      .toList();

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
        _OccupancyBar(
          zone: zones.isEmpty ? 'الصالة' : zones.first,
          total: _tables.length,
          occupied: occupied,
        ),
        const SizedBox(height: 12),
        if (_tables.isNotEmpty)
          _StatusChips(
            counts: {
              for (final t in TableStatus.values)
                t: _tables.where((x) => x.status == t).length,
            },
            selected: _filter,
            onSelect: (t) => setState(() => _filter = t),
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
                itemCount: _visibleIn(zone).length,
                itemBuilder: (context, i) {
                  final table = _visibleIn(zone)[i];
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

/// The design's occupancy strip: the hall name over its table count, with a
/// real occupancy percentage on the right. The percentage is derived from the
/// loaded tables, so an empty floor reads 0% rather than a placeholder.
class _OccupancyBar extends StatelessWidget {
  const _OccupancyBar({
    required this.zone,
    required this.total,
    required this.occupied,
  });

  final String zone;
  final int total;
  final int occupied;

  @override
  Widget build(BuildContext context) {
    final percent = total == 0 ? 0 : (occupied * 100 / total).round();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceLow,
        border: Border.all(color: AppColors.borderSubtle),
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surfaceHigh,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            child: const Icon(Icons.meeting_room_outlined,
                size: 18, color: AppColors.brand),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(zone,
                    overflow: TextOverflow.ellipsis, style: AppText.bodyStrong),
                Text(
                  total == 0
                      ? 'مفيش طاولات متعرفة لسه.'
                      : 'إجمالي $total طاولة • معدل الإشغال $percent%',
                  style: AppText.caption,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Text('$percent%',
              style: AppText.kpiValue.copyWith(fontSize: 16)),
        ],
      ),
    );
  }
}

/// The design's status pills, each carrying its own count. Tapping the active
/// pill clears the filter, so there is always a way back to every table
/// without hunting for a separate "all" control.
class _StatusChips extends StatelessWidget {
  const _StatusChips({
    required this.counts,
    required this.selected,
    required this.onSelect,
  });

  final Map<TableStatus, int> counts;
  final TableStatus? selected;

  /// Null clears the filter; a status narrows to it.
  final ValueChanged<TableStatus?> onSelect;

  Color _tone(TableStatus status) => switch (status) {
        TableStatus.vacant => AppColors.secondary,
        TableStatus.occupied => AppColors.brand,
        TableStatus.billRequested => AppColors.tertiary,
      };

  @override
  Widget build(BuildContext context) {
    final total = counts.values.fold(0, (a, b) => a + b);
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _pill(
            label: 'الكل',
            count: total,
            active: selected == null,
            tone: AppColors.brand,
            onTap: () => onSelect(null),
          ),
          for (final status in TableStatus.values) ...[
            const SizedBox(width: 8),
            _pill(
              label: status.label,
              count: counts[status] ?? 0,
              active: selected == status,
              tone: _tone(status),
              onTap: () => onSelect(status),
            ),
          ],
        ],
      ),
    );
  }

  Widget _pill({
    required String label,
    required int count,
    required bool active,
    required Color tone,
    required VoidCallback onTap,
  }) {
    final fg = active ? AppColors.onBrand : AppColors.fgMuted;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? tone : AppColors.surfaceSunken,
          border: Border.all(
              color: active ? tone : AppColors.borderSubtle),
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: AppText.label
                    .copyWith(color: fg, fontWeight: FontWeight.w600)),
            const SizedBox(width: 6),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: active
                    ? AppColors.onBrand.withValues(alpha: 0.20)
                    : AppColors.surfaceCard,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text('$count',
                  style: AppText.caption.copyWith(
                      fontSize: 11,
                      color: fg,
                      fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
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

  /// The design colours each state with its own family: mint for a free
  /// table, amber for one mid-service, periwinkle for one awaiting its bill.
  Color get _accent => switch (table.status) {
        TableStatus.vacant => AppColors.secondary,
        TableStatus.occupied => AppColors.brand,
        TableStatus.billRequested => AppColors.tertiary,
      };

  /// How long the party has been seated, in the design's compact "42 د" form.
  /// Null when the table has no seating timestamp — the badge is then simply
  /// absent rather than showing a zero that would read as "just seated".
  String? get _elapsed {
    final at = table.seatedAt;
    if (at == null) return null;
    final minutes = DateTime.now().difference(at).inMinutes;
    if (minutes < 0) return null;
    if (minutes < 60) return '$minutes د';
    return '${minutes ~/ 60} س ${minutes % 60} د';
  }

  @override
  Widget build(BuildContext context) {
    final accent = _accent;
    final elapsed = _elapsed;
    final occupied = table.status != TableStatus.vacant;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceLow,
        border: Border.all(color: AppColors.borderSubtle),
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The design's table-code block: a small square carrying the
              // word "طاولة" over the code, tinted with the state colour.
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.surfaceHigh,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('طاولة',
                        style: AppText.caption.copyWith(
                            fontSize: 9, color: AppColors.fgMuted)),
                    Text(
                      table.code,
                      style: AppText.kpiValue.copyWith(fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: accent,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            table.status.label,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.bodyStrong
                                .copyWith(fontSize: 13, color: accent),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      occupied
                          ? '${table.partySize} أفراد'
                              '${table.steward.isEmpty ? '' : ' · ${table.steward}'}'
                          : 'السعة القصوى: ${table.capacity} أفراد',
                      style: AppText.caption,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (table.zone.isNotEmpty)
                      Text(table.zone,
                          style: AppText.caption, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              if (elapsed != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceHigh,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.timer_outlined, size: 13, color: accent),
                      const SizedBox(width: 4),
                      Text(elapsed,
                          style: AppText.caption
                              .copyWith(color: accent, fontSize: 11)),
                    ],
                  ),
                ),
            ],
          ),
          const Spacer(),
          // The design closes each occupied card with the running bill on its
          // own sunken strip and a full-width action beneath it.
          if (occupied) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.surfaceCard,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          table.status == TableStatus.billRequested
                              ? 'المطلوب سداده'
                              : 'الحساب الجاري',
                          style: AppText.caption.copyWith(fontSize: 10),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          money(table.runningTotal),
                          overflow: TextOverflow.ellipsis,
                          style: AppText.kpiValue.copyWith(fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                  if ((table.currentOrderRef ?? '').isNotEmpty)
                    Text(table.currentOrderRef!, style: AppText.monoSmall),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
          switch (table.status) {
            TableStatus.vacant => RmsButton(
                label: 'فتح طلب جديد',
                icon: Icons.add_circle_outlined,
                dense: true,
                onPressed: onSeat,
              ),
            TableStatus.occupied => RmsButton(
                label: 'عرض السلة / الدفع',
                icon: Icons.shopping_cart_checkout_outlined,
                dense: true,
                onPressed: onBill,
              ),
            TableStatus.billRequested => RmsButton(
                label: 'تحصيل كاش / فيزا',
                icon: Icons.payments_outlined,
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

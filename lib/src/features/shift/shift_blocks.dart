import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/status.dart';
import '../../domain/models/cash_session.dart';
import '../../domain/models/order.dart';
import '../../domain/models/order_type.dart';
import '../common/format.dart';

/// The design's shift header: the open/closed state, when the shift started
/// and how long it has run, plus the drawer total against its opening float.
///
/// Every figure here is read from the live [CashSession]. With no session
/// open the strip says so rather than showing zeros that would read like a
/// real till balance.
class ShiftStatusStrip extends StatelessWidget {
  const ShiftStatusStrip({super.key, required this.session});

  final CashSession? session;

  /// "4h 50m" as the design writes it, in Arabic hours and minutes.
  static String _elapsed(DateTime from, DateTime now) {
    final d = now.difference(from);
    if (d.isNegative) return '0 د';
    final hours = d.inHours;
    final minutes = d.inMinutes % 60;
    if (hours == 0) return '$minutes د';
    return '${hours} س ${minutes} د';
  }

  static String _clock(DateTime at) {
    final h = at.hour % 12 == 0 ? 12 : at.hour % 12;
    final m = at.minute.toString().padLeft(2, '0');
    return '$h:$m ${at.hour < 12 ? 'ص' : 'م'}';
  }

  @override
  Widget build(BuildContext context) {
    final s = session;
    final open = s != null && s.isOpen;
    final accent = open ? AppColors.secondary : AppColors.fgMuted;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceLow,
        border: Border.all(color: AppColors.borderSubtle),
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
      ),
      child: Row(
        children: [
          Icon(open ? Icons.lock_open_outlined : Icons.lock_outline,
              size: 18, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        s == null
                            ? 'مفيش وردية مفتوحة'
                            : open
                                ? 'الوردية مفتوحة'
                                : 'الوردية مقفولة',
                        overflow: TextOverflow.ellipsis,
                        style: AppText.bodyStrong.copyWith(fontSize: 13),
                      ),
                    ),
                    if (s != null) ...[
                      const SizedBox(width: 8),
                      Tag(label: s.status.label, tone: open ? StatusTone.positive : StatusTone.neutral),
                    ],
                  ],
                ),
                if (s != null)
                  Text(
                    'بدأت ${_clock(s.openedAt)} (${_elapsed(s.openedAt, DateTime.now())})',
                    style: AppText.caption,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          // The drawer figure: the opening float is a recorded number, and the
          // difference between it and today's takings is what the close-out
          // counts against.
          if (s != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('عهدة البداية',
                    style: AppText.caption.copyWith(fontSize: 10)),
                Text(money(s.openingFloat),
                    style: AppText.kpiValue.copyWith(fontSize: 15)),
              ],
            ),
        ],
      ),
    );
  }
}

/// The design's live ticket rail: filter chips per service channel, each with
/// its real count, and today's orders listed with the channel they were sold
/// on.
///
/// Only the channels the model knows about are offered. The design also
/// filters by kitchen state (in preparation / ready / on the way), which needs
/// a kitchen state this app deliberately does not have — so those chips are
/// absent rather than shown empty.
class TicketQueue extends StatefulWidget {
  const TicketQueue({super.key, required this.orders});

  final List<Order> orders;

  @override
  State<TicketQueue> createState() => _TicketQueueState();
}

class _TicketQueueState extends State<TicketQueue> {
  OrderType? _channel;

  Color _tone(OrderType type) => switch (type) {
        OrderType.dineIn => AppColors.brand,
        OrderType.takeaway => AppColors.tertiary,
        OrderType.delivery => AppColors.secondary,
      };

  IconData _icon(OrderType type) => switch (type) {
        OrderType.dineIn => Icons.table_restaurant_outlined,
        OrderType.takeaway => Icons.takeout_dining_outlined,
        OrderType.delivery => Icons.moped_outlined,
      };

  List<Order> get _visible => _channel == null
      ? widget.orders
      : widget.orders.where((o) => o.orderType == _channel).toList();

  @override
  Widget build(BuildContext context) {
    final counts = {
      for (final t in OrderType.values)
        t: widget.orders.where((o) => o.orderType == t).length,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.point_of_sale_outlined,
                size: 18, color: AppColors.brand),
            const SizedBox(width: 8),
            Expanded(
              child: Text('طابور التذاكر المباشر',
                  style: AppText.bodyStrong.copyWith(fontSize: 13)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _chip(
                label: 'الكل',
                count: widget.orders.length,
                active: _channel == null,
                tone: AppColors.brand,
                onTap: () => setState(() => _channel = null),
              ),
              for (final type in OrderType.values) ...[
                const SizedBox(width: 8),
                _chip(
                  label: type.label,
                  count: counts[type] ?? 0,
                  active: _channel == type,
                  tone: _tone(type),
                  onTap: () => setState(() => _channel = type),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (_visible.isEmpty)
          const Text('مفيش تذاكر على القناة دي النهاردة.',
              style: AppText.caption)
        else
          for (final order in _visible)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _TicketRow(order: order, tone: _tone(order.orderType),
                  icon: _icon(order.orderType)),
            ),
      ],
    );
  }

  Widget _chip({
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
          border:
              Border.all(color: active ? tone : AppColors.borderSubtle),
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: AppText.label
                    .copyWith(color: fg, fontWeight: FontWeight.w600)),
            const SizedBox(width: 6),
            Text('$count',
                style: AppText.caption
                    .copyWith(fontSize: 11, color: fg)),
          ],
        ),
      ),
    );
  }
}

class _TicketRow extends StatelessWidget {
  const _TicketRow({
    required this.order,
    required this.tone,
    required this.icon,
  });

  final Order order;
  final Color tone;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final names = order.items.map((i) => i.name).join('، ');
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceLow,
        border: Border.all(color: AppColors.borderSubtle),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surfaceHigh,
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: Icon(icon, size: 15, color: tone),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(order.provisionalOrderNumber,
                        style: AppText.bodyStrong.copyWith(fontSize: 13)),
                    const SizedBox(width: 6),
                    Text('· ${order.orderType.label}',
                        style: AppText.caption.copyWith(fontSize: 11)),
                  ],
                ),
                if (names.isNotEmpty)
                  Text(
                    names,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.caption,
                  ),
              ],
            ),
          ),
          Text(money(order.total),
              style: AppText.kpiValue.copyWith(fontSize: 14)),
        ],
      ),
    );
  }
}

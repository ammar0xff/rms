import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/blocks.dart';
import '../../domain/models/order_type.dart';
import '../common/format.dart';

/// The design's "توزيع قنوات البيع" section: a header with the channel count,
/// a single stacked bar split by share, then one column per channel carrying
/// its colour, its percentage and its takings.
///
/// Every figure is derived from today's real orders. A channel with no sales
/// still appears — it is part of the design's three-column shape — but at 0%
/// and nothing, rather than being hidden, so the columns never reflow as the
/// day fills up.
class ChannelBreakdown extends StatelessWidget {
  const ChannelBreakdown({super.key, required this.sales});

  final Map<OrderType, double> sales;

  static const _order = [OrderType.dineIn, OrderType.delivery, OrderType.takeaway];

  /// The design paints each channel in its own family: mint for the hall,
  /// periwinkle for delivery, amber for takeaway.
  static Color tone(OrderType type) => switch (type) {
        OrderType.dineIn => AppColors.secondary,
        OrderType.delivery => AppColors.tertiary,
        OrderType.takeaway => AppColors.brand,
      };

  @override
  Widget build(BuildContext context) {
    final total = sales.values.fold(0.0, (a, b) => a + b);
    final active = _order.where((t) => (sales[t] ?? 0) > 0).length;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.borderStrong),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.pie_chart_outline,
                  size: 16, color: AppColors.brand),
              const SizedBox(width: 8),
              Expanded(
                child: Text('توزيع قنوات البيع',
                    style: AppText.bodyStrong.copyWith(fontSize: 13)),
              ),
              Text('$active قنوات نشطة', style: AppText.caption),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          // The single stacked bar. Flex carries the share, so no percentage
          // arithmetic is needed and a zero-total day degrades to nothing
          // rather than dividing by zero.
          if (total > 0)
            Row(
              children: [
                for (final type in _order)
                  if ((sales[type] ?? 0) > 0)
                    Expanded(
                      flex: ((sales[type] ?? 0) * 1000).round().clamp(1, 1000000),
                      child: Container(
                        height: 8,
                        margin: const EdgeInsets.only(left: 2),
                        decoration: BoxDecoration(
                          color: tone(type),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
              ],
            ),
          const SizedBox(height: 6),
          const Divider(height: 1),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final type in _order) ...[
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceSunken,
                      borderRadius:
                          BorderRadius.circular(AppSpacing.radiusSm),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: tone(type),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(type.label,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppText.body.copyWith(fontSize: 12)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        LtrIsolate(
                          child: Text(
                            '${total == 0 ? 0 : (((sales[type] ?? 0) / total) * 100).round()}%',
                            style: AppText.kpiValue
                                .copyWith(fontSize: 16, color: tone(type)),
                          ),
                        ),
                        LtrIsolate(
                          child: Text(
                            money(sales[type] ?? 0),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.monoSmall
                                .copyWith(color: tone(type)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (type != _order.last) const SizedBox(width: 6),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

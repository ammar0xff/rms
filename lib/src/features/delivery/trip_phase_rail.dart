import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../domain/models/delivery.dart';

/// Where a stop sits in its trip, using the design's four phases:
/// تم الاستلام ← في الطريق ← عند العميل ← تسليم وكش.
///
/// The phases are derived from [DeliveryState] rather than tracked separately,
/// so a stop cannot claim a phase the repository does not agree with. A failed
/// or returned stop leaves the rail: it has no onward phase, and the design
/// shows the failure on the card itself rather than as a stopped progress bar.
enum TripPhase { pickedUp, onRoute, atCustomer, handedOver }

extension TripPhaseX on TripPhase {
  static const _labels = ['تم الاستلام', 'في الطريق', 'عند العميل', 'تسليم وكش'];

  String get label => _labels[index];

  static const _icons = [
    Icons.inventory_2_outlined,
    Icons.near_me_outlined,
    Icons.person_pin_circle_outlined,
    Icons.task_alt,
  ];

  IconData get icon => _icons[index];

  /// The phase a state corresponds to, or null when the stop has left the
  /// happy path and the rail should not pretend otherwise.
  static TripPhase? of(DeliveryState state) => switch (state) {
        DeliveryState.waiting || DeliveryState.assigned => TripPhase.pickedUp,
        DeliveryState.onRoute => TripPhase.atCustomer,
        DeliveryState.delivered => TripPhase.handedOver,
        DeliveryState.failed || DeliveryState.returned => null,
      };
}

/// The trip progress rail: the design's "حالة المشوار · مرحلة 2 من 4", with a
/// completed step, an active step, and the ones still ahead.
class TripPhaseRail extends StatelessWidget {
  const TripPhaseRail({super.key, required this.state});

  final DeliveryState state;

  @override
  Widget build(BuildContext context) {
    final active = TripPhaseX.of(state);
    if (active == null) return const SizedBox.shrink();
    final index = active.index;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('حالة المشوار', style: AppText.label),
            const SizedBox(width: 8),
            Text(
              'مرحلة ${index + 1} من 4',
              style: AppText.monoSmall.copyWith(color: AppColors.fg),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // The rail is a Row of Expanded steps rather than a single painted
        // line: each step owns its own dot, connector and label, so a long
        // Arabic label wraps inside its third instead of the whole bar
        // overflowing a narrow screen.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < TripPhase.values.length; i++) ...[
              if (i > 0)
                Expanded(
                  child: Container(
                    height: 2,
                    margin: const EdgeInsets.only(top: 13),
                    color: i <= index
                        ? AppColors.brand
                        : AppColors.borderStrong,
                  ),
                ),
              Expanded(
                flex: 3,
                child: Column(
                  children: [
                    Icon(
                      TripPhaseX._icons[i],
                      size: 16,
                      color: i <= index
                          ? AppColors.brand
                          : AppColors.fgGhost,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      TripPhaseX._labels[i],
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption.copyWith(
                        fontSize: 10,
                        color: i == index
                            ? AppColors.brand
                            : i < index
                                ? AppColors.fgSecondary
                                : AppColors.fgGhost,
                        fontWeight:
                            i == index ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

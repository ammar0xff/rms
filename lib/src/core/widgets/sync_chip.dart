import 'package:flutter/material.dart';

import '../state/sync_monitor.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text.dart';
import 'status.dart';

class SyncChip extends StatelessWidget {
  const SyncChip({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final monitor = SyncMonitor.instance;
    return AnimatedBuilder(
      animation: monitor,
      builder: (context, _) {
        final (label, tone) = monitor.online
            ? (monitor.pending > 0 ? 'جارٍ المزامنة (${monitor.pending})' : 'متصل', StatusTone.positive)
            // Short on purpose: this chip lives in the 48px top bar next to
            // the title and action buttons, and the counts live in the sync
            // center. A long label overflows narrow screens.
            : ('غير متصل', StatusTone.warning);
        final color = toneColor(tone);
        return Tooltip(
          message: monitor.online
              ? 'متصل · آخر مزامنة قبل ${monitor.sinceLastSync.inMinutes} د'
              : 'يعمل دون اتصال. التغييرات محفوظة محليًا.',
          child: InkWell(
            // Display-only unless a caller wires an action. The old default
            // flipped a display boolean that feeds real decisions (the update
            // gate, finalize buttons) while touching neither the link nor the
            // sync engine — one curious tap put the app in a state that
            // disagreed with reality until the next refresh overwrote it.
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.06),
                border: Border.all(color: color.withValues(alpha: 0.2)),
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  StatusDot(tone: tone),
                  const SizedBox(width: 7),
                  Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.caption.copyWith(
                      fontWeight: FontWeight.w500,
                      color: color.withValues(alpha: 0.9),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class SyncStatRow extends StatelessWidget {
  const SyncStatRow({super.key});

  @override
  Widget build(BuildContext context) {
    final monitor = SyncMonitor.instance;
    return AnimatedBuilder(
      animation: monitor,
      builder: (context, _) => Row(
        children: [
          _cell('قيد الانتظار', '${monitor.pending}', AppColors.fgBright),
          _divider(),
          _cell('فشلها', '${monitor.failed}', AppColors.negative),
          _divider(),
          _cell('تعارضات', '${monitor.conflicts}', AppColors.warning),
        ],
      ),
    );
  }

  /// One flexing cell: the label ellipsizes inside its third of the card
  /// instead of the row overflowing narrow screens. The flex has to live
  /// here, on the outer row's children — one level deeper cannot save it.
  Widget _cell(String label, String value, Color color) {
    return Expanded(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(label,
                overflow: TextOverflow.ellipsis, style: AppText.label),
          ),
          const SizedBox(width: 5),
          Text(value,
              style: AppText.caption.copyWith(
                  color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _divider() => Container(
        width: 1,
        height: 12,
        color: AppColors.borderStrong,
        margin: const EdgeInsets.symmetric(horizontal: 6),
      );
}

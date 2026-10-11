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
            : ('غير متصل · ${monitor.pending} قيد الانتظار', StatusTone.warning);
        final color = toneColor(tone);
        return Tooltip(
          message: monitor.online
              ? 'متصل · آخر مزامنة قبل ${monitor.sinceLastSync.inMinutes} د'
              : 'يعمل دون اتصال. التغييرات محفوظة محليًا.',
          child: InkWell(
            onTap: onTap ?? monitor.toggleConnectivity,
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            child: Container(
              height: 28,
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
                    style: AppText.caption.copyWith(
                      fontSize: 11,
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
        mainAxisSize: MainAxisSize.min,
        children: [
          _item(context, 'قيد الانتظار', '${monitor.pending}', AppColors.fgBright),
          const SizedBox(width: 12),
          Container(width: 1, height: 12, color: AppColors.borderStrong),
          const SizedBox(width: 12),
          _item(context, 'فشلها', '${monitor.failed}', AppColors.negative),
          const SizedBox(width: 12),
          Container(width: 1, height: 12, color: AppColors.borderStrong),
          const SizedBox(width: 12),
          _item(context, 'تعارضات', '${monitor.conflicts}', AppColors.warning),
        ],
      ),
    );
  }

  Widget _item(BuildContext context, String label, String value, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: AppText.label.copyWith(fontSize: 9.5)),
        const SizedBox(width: 5),
        Text(value, style: AppText.caption.copyWith(color: color, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

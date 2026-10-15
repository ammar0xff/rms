import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text.dart';

enum StatusTone { neutral, positive, negative, warning, info, brand }

Color toneColor(StatusTone tone) => switch (tone) {
      StatusTone.positive => AppColors.positive,
      StatusTone.negative => AppColors.negative,
      StatusTone.warning => AppColors.warning,
      StatusTone.info => AppColors.info,
      StatusTone.brand => AppColors.brand,
      StatusTone.neutral => AppColors.fgMuted,
    };

class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.tone, this.size = 5});

  final StatusTone tone;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: toneColor(tone).withValues(alpha: 0.85),
        shape: BoxShape.circle,
      ),
    );
  }
}

class StatusText extends StatelessWidget {
  const StatusText({super.key, required this.label, required this.tone});

  final String label;
  final StatusTone tone;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        StatusDot(tone: tone),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: AppText.caption.copyWith(color: AppColors.fgSecondary),
          ),
        ),
      ],
    );
  }
}

class Tag extends StatelessWidget {
  const Tag({
    super.key,
    required this.label,
    this.tone = StatusTone.neutral,
    this.icon,
  });

  final String label;
  final StatusTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final color = toneColor(tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.22)),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: AppText.label.copyWith(
                color: color,
                letterSpacing: 0.2,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

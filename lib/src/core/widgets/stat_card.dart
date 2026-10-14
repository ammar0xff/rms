import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import 'charts.dart';
import 'surface_card.dart';

class HeroKpi extends StatelessWidget {
  const HeroKpi({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.delta,
    this.deltaTone = DeltaTone.positive,
    this.subtext,
    this.spark,
  });

  final String label;
  final String value;
  final String? unit;
  final String? delta;
  final DeltaTone deltaTone;
  final String? subtext;
  final List<double>? spark;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label.toUpperCase(), style: AppText.label),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    // 44px hero figures overflow narrow cards; scale down
                    // rather than clip.
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(value, style: AppText.hero),
                      ),
                    ),
                    if (unit != null) ...[
                      const SizedBox(width: 6),
                      Text(unit!,
                          style: AppText.kpiValue.copyWith(
                            color: AppColors.fgMuted,
                            fontSize: 16,
                          )),
                    ],
                  ],
                ),
                if (delta != null || subtext != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (delta != null)
                        Flexible(
                          child: Text(
                            delta!,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.caption.copyWith(
                              color: deltaTone.color,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      if (delta != null && subtext != null)
                        const SizedBox(width: 8),
                      if (subtext != null)
                        Expanded(
                          child: Text(
                            subtext!,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.caption,
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (spark != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Sparkline(values: spark!),
            ),
        ],
      ),
    );
  }
}

enum DeltaTone {
  positive(AppColors.positive),
  negative(AppColors.negative),
  neutral(AppColors.fgMuted);

  const DeltaTone(this.color);
  final Color color;
}

class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    this.delta,
    this.deltaTone = DeltaTone.positive,
    this.tone,
  });

  final String label;
  final String value;
  final String? delta;
  final DeltaTone deltaTone;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      level: SurfaceLevel.secondary,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.label.copyWith(color: AppColors.fgMuted)),
                const SizedBox(height: 6),
                Text(value,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.kpiValue.copyWith(
                      color: tone ?? AppColors.fgBright,
                    )),
              ],
            ),
          ),
          if (delta != null)
            Flexible(
              child: Text(
                delta!,
                overflow: TextOverflow.ellipsis,
                style: AppText.caption.copyWith(
                  color: deltaTone.color,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class ProgressBar extends StatelessWidget {
  const ProgressBar({
    super.key,
    required this.value,
    this.color = AppColors.brand,
    this.height = 3,
  });

  final double value;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: LinearProgressIndicator(
        value: value.clamp(0.0, 1.0).toDouble(),
        minHeight: height,
        backgroundColor: AppColors.borderStrong,
        valueColor: AlwaysStoppedAnimation(color),
      ),
    );
  }
}

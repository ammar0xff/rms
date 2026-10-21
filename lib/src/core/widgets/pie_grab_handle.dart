import 'package:flutter/material.dart';
import '../theme/pie_colors.dart';
import '../theme/pie_radius.dart';

/// Standard modal bottom sheet grab handle pill (مقبض سحب النوافذ السفلية).
///
/// Implements tactile affordance per Steve Jobs / Jony Ive minimalism:
/// - 36px width, 4px height
/// - High-precision subtle border tone
/// - Standardized top/bottom rhythm
class PieGrabHandle extends StatelessWidget {
  const PieGrabHandle({
    super.key,
    this.margin = const EdgeInsets.only(top: 10, bottom: 8),
    this.width = 36.0,
    this.height = 4.0,
    this.color = PieColors.border,
  });

  final EdgeInsetsGeometry margin;
  final double width;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: margin,
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: color,
          borderRadius: PieRadius.borderSm,
        ),
      ),
    );
  }
}

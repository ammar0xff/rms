import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class Sparkline extends StatelessWidget {
  const Sparkline({
    super.key,
    required this.values,
    this.color = AppColors.fgMuted,
    this.width = 120,
    this.height = 44,
    this.filled = true,
  });

  final List<double> values;
  final Color color;
  final double width;
  final double height;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(width, height),
      painter: _SparkPainter(values, color, filled),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.values, this.color, this.filled);

  final List<double> values;
  final Color color;
  final bool filled;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final maxV = values.reduce(math.max);
    final minV = values.reduce(math.min);
    final range = (maxV - minV) == 0 ? 1.0 : (maxV - minV);
    final dx = size.width / (values.length - 1);

    Offset pointAt(int i) {
      final x = dx * i;
      final y = size.height - ((values[i] - minV) / range) * size.height;
      return Offset(x, y.clamp(0.0, size.height).toDouble());
    }

    final path = Path()..moveTo(pointAt(0).dx, pointAt(0).dy);
    for (var i = 1; i < values.length; i++) {
      final p = pointAt(i);
      path.lineTo(p.dx, p.dy);
    }

    if (filled) {
      final fillPath = Path.from(path)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();
      canvas.drawPath(
        fillPath,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              color.withValues(alpha: 0.06),
              color.withValues(alpha: 0.0),
            ],
          ).createShader(Offset.zero & size),
      );
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.25
        ..strokeCap = StrokeCap.round,
    );

    final last = pointAt(values.length - 1);
    canvas.drawCircle(last, 2.5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) =>
      old.values != values || old.color != color;
}

class MiniBars extends StatelessWidget {
  const MiniBars({
    super.key,
    required this.values,
    this.color = AppColors.fgMuted,
    this.height = 120,
    this.highlightIndex,
    this.gridFractions = const [0.25, 0.5],
    this.gridColor = const Color(0x1AFFFFFF),
  });

  final List<double> values;
  final Color color;
  final double height;
  final int? highlightIndex;
  final List<double> gridFractions;
  final Color gridColor;

  @override
  Widget build(BuildContext context) {
    final maxV = values.isEmpty ? 1.0 : values.reduce(math.max);
    final bars = Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < values.length; i++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: FractionallySizedBox(
                heightFactor: (values[i] / maxV).clamp(0.04, 1.0).toDouble(),
                alignment: Alignment.bottomCenter,
                child: Container(
                  decoration: BoxDecoration(
                    color: (highlightIndex == null || highlightIndex == i)
                        ? color.withValues(alpha: 0.75)
                        : color.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          ),
      ],
    );

    if (gridFractions.isEmpty) {
      return SizedBox(height: height, child: bars);
    }

    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(painter: _GridPainter(gridFractions, gridColor)),
          bars,
        ],
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  _GridPainter(this.fractions, this.color);

  final List<double> fractions;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (final f in fractions) {
      final y = size.height * (1 - f);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter old) =>
      old.fractions != fractions || old.color != color;
}

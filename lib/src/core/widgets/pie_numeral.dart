import 'package:flutter/material.dart';
import '../theme/pie_colors.dart';
import '../theme/pie_typography.dart';

/// A widget that safely renders numerals in tabular monospace and isolates
/// them in Left-to-Right direction within an RTL Arabic layout.
///
/// Prevents order numbers, currencies, elapsed times (MM:SS), and negative deltas
/// from being rearranged or flipped by Bidi algorithms.
class PieNumeral extends StatelessWidget {
  const PieNumeral(
    this.text, {
    super.key,
    this.style,
    this.prefix,
    this.suffix,
    this.color,
    this.fontSize,
    this.fontWeight,
  });

  /// Formatted number / decimal value
  factory PieNumeral.value(
    num value, {
    Key? key,
    int? decimals,
    TextStyle? style,
    String? prefix,
    String? suffix,
    Color? color,
    double? fontSize,
    FontWeight? fontWeight,
  }) {
    return PieNumeral(
      decimals != null ? value.toStringAsFixed(decimals) : value.toString(),
      key: key,
      style: style,
      prefix: prefix,
      suffix: suffix,
      color: color,
      fontSize: fontSize,
      fontWeight: fontWeight,
    );
  }

  /// Formatted money in Egyptian Pounds (`ج.م`)
  factory PieNumeral.money(
    num amount, {
    TextStyle? style,
    Color? color,
    double? fontSize,
    FontWeight? fontWeight,
    String? prefix,
  }) {
    return PieNumeral(
      amount.toStringAsFixed(2),
      suffix: ' ج.م',
      prefix: prefix,
      style: style,
      color: color,
      fontSize: fontSize,
      fontWeight: fontWeight,
    );
  }

  /// Formatted counter / count integer
  factory PieNumeral.count(
    int count, {
    TextStyle? style,
    Color? color,
    double? fontSize,
    FontWeight? fontWeight,
    String? prefix,
  }) {
    return PieNumeral(
      count.toString(),
      prefix: prefix,
      style: style,
      color: color,
      fontSize: fontSize,
      fontWeight: fontWeight,
    );
  }

  /// Formatted timer / clock e.g. "14:20"
  factory PieNumeral.time(
    String time, {
    TextStyle? style,
    Color? color,
    double? fontSize,
  }) {
    return PieNumeral(
      time,
      style: style,
      color: color,
      fontSize: fontSize,
    );
  }

  final String text;
  final TextStyle? style;
  final String? prefix;
  final String? suffix;
  final Color? color;
  final double? fontSize;
  final FontWeight? fontWeight;

  @override
  Widget build(BuildContext context) {
    var baseStyle = style ?? PieTypography.monoBody;
    if (color != null) baseStyle = baseStyle.copyWith(color: color);
    if (fontSize != null) baseStyle = baseStyle.copyWith(fontSize: fontSize);
    if (fontWeight != null) baseStyle = baseStyle.copyWith(fontWeight: fontWeight);

    final numWidget = Directionality(
      textDirection: TextDirection.ltr,
      child: Text(
        text,
        style: baseStyle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );

    if (prefix == null && suffix == null) {
      return numWidget;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        if (prefix != null)
          Flexible(
            fit: FlexFit.loose,
            child: Text(
              prefix!,
              style: PieTypography.caption.copyWith(
                color: color ?? PieColors.inkSecondary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        Flexible(
          fit: FlexFit.loose,
          child: numWidget,
        ),
        if (suffix != null)
          Flexible(
            fit: FlexFit.loose,
            child: Padding(
              padding: const EdgeInsets.only(right: 2),
              child: Text(
                suffix!,
                style: PieTypography.caption.copyWith(
                  color: color ?? PieColors.inkSecondary,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
      ],
    );
  }
}

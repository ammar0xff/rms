import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

class PageBody extends StatelessWidget {
  /// On wide screens the content caps here and centers; phones keep
  /// edge-to-edge content with adaptive padding.
  static const double maxContentWidth = 1160;

  const PageBody({
    super.key,
    required this.children,
    this.scrollable = true,
    this.padding,
  });

  final List<Widget> children;
  final bool scrollable;

  /// Null means adaptive: 16px on phones, [AppSpacing.pagePadding] otherwise.
  /// 24px a side is 13% of a 360px screen gone to chrome.
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.section),
          children[i],
        ],
      ],
    );

    Widget content = padding == null
        ? LayoutBuilder(
            builder: (context, c) {
              final padded = Padding(
                padding: EdgeInsets.all(
                    c.maxWidth < 600 ? 16 : AppSpacing.pagePadding),
                child: column,
              );
              // A table or hero stretched across a 1920px monitor is chrome,
              // not layout: cap the content and center it on wide screens.
              if (c.maxWidth <= maxContentWidth) return padded;
              return Center(
                child: ConstrainedBox(
                  constraints:
                      const BoxConstraints(maxWidth: maxContentWidth),
                  child: padded,
                ),
              );
            },
          )
        : Padding(padding: padding!, child: column);
    if (!scrollable) return content;
    return Scrollbar(
      child: SingleChildScrollView(child: content),
    );
  }
}

class GridRow extends StatelessWidget {
  const GridRow({super.key, required this.children, this.gap = AppSpacing.cardGap});

  final List<Widget> children;
  final double gap;

  @override
  Widget build(BuildContext context) {
    // Three stat cards at 96px each are unreadable; stack them instead.
    return ResponsiveRow(children: children, gap: gap, breakpoint: 560);
  }
}

/// A [Row] of equally-weighted children on wide screens that becomes a
/// [Column] on narrow ones.
///
/// This is the fix for the most repeated mobile bug in the app: a bare Row of
/// Expanded panels with no narrow fallback, which squeezes every child into a
/// ~100px lane on a phone. Callers keep writing the desktop layout; phones get
/// the stacked one for free.
class ResponsiveRow extends StatelessWidget {
  const ResponsiveRow({
    super.key,
    required this.children,
    this.gap = AppSpacing.cardGap,
    this.breakpoint = 600,
  });

  final List<Widget> children;
  final double gap;
  final double breakpoint;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth >= breakpoint) {
          // No IntrinsicHeight here: descendants such as RmsTable contain a
          // LayoutBuilder, which cannot provide intrinsic dimensions and
          // crashes the intrinsic pass. Cards size independently instead.
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) SizedBox(width: gap),
                Expanded(child: children[i]),
              ],
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) SizedBox(height: gap),
              children[i],
            ],
          ],
        );
      },
    );
  }
}

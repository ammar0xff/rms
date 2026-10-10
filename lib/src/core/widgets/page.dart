import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

class PageBody extends StatelessWidget {
  const PageBody({
    super.key,
    required this.children,
    this.scrollable = true,
    this.padding = const EdgeInsets.all(AppSpacing.pagePadding),
  });

  final List<Widget> children;
  final bool scrollable;
  final EdgeInsetsGeometry padding;

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

    final content = Padding(padding: padding, child: column);
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) SizedBox(width: gap),
          Expanded(child: children[i]),
        ],
      ],
    );
  }
}

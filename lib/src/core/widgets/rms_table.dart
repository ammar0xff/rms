import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text.dart';

class RmsColumn {
  const RmsColumn(
    this.label, {
    this.flex = 1,
    this.width,
    this.align = TextAlign.left,
  });

  final String label;
  final int flex;
  final double? width;
  final TextAlign align;
}

class RmsTable extends StatelessWidget {
  const RmsTable({
    super.key,
    required this.columns,
    required this.rows,
    this.onRowTap,
  });

  final List<RmsColumn> columns;
  final List<List<Widget>> rows;
  final void Function(int index)? onRowTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: const BoxDecoration(
            color: AppColors.surfaceSunken,
            border: Border(
              top: BorderSide(color: AppColors.borderSubtle),
              bottom: BorderSide(color: AppColors.borderSubtle),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: _row(
            columns
                .map((c) => Align(
                      alignment: c.align == TextAlign.right
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Text(c.label.toUpperCase(), style: AppText.tableHeader),
                    ))
                .toList(),
          ),
        ),
        for (var i = 0; i < rows.length; i++)
          _BodyRow(
            children: rows[i],
            columns: columns,
            last: i == rows.length - 1,
            onTap: onRowTap == null ? null : () => onRowTap!(i),
          ),
      ],
    );
  }

  static Widget _row(List<Widget> children) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: _spacers(children),
    );
  }

  static List<Widget> _spacers(List<Widget> children) {
    return children;
  }
}

class _BodyRow extends StatefulWidget {
  const _BodyRow({
    required this.children,
    required this.columns,
    required this.last,
    this.onTap,
  });

  final List<Widget> children;
  final List<RmsColumn> columns;
  final bool last;
  final VoidCallback? onTap;

  @override
  State<_BodyRow> createState() => _BodyRowState();
}

class _BodyRowState extends State<_BodyRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final cells = <Widget>[];
    for (var i = 0; i < widget.columns.length; i++) {
      final col = widget.columns[i];
      final cell = i < widget.children.length
          ? widget.children[i]
          : const SizedBox.shrink();
      final wrapped = Align(
        alignment: col.align == TextAlign.right
            ? Alignment.centerRight
            : Alignment.centerLeft,
        child: cell,
      );
      cells.add(
        col.width != null
            ? SizedBox(width: col.width, child: wrapped)
            : Expanded(flex: col.flex, child: wrapped),
      );
    }

    return MouseRegion(
      cursor: widget.onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: _hover ? Colors.white.withValues(alpha: 0.012) : null,
            border: widget.last
                ? null
                : const Border(
                    bottom: BorderSide(color: AppColors.borderFaint),
                  ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: cells,
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../theme/pie_colors.dart';
import '../theme/pie_typography.dart';
import 'pie_button.dart';

/// Honest Empty State
///
/// Principle: Never fabricate fake rows or pretend figures.
/// When a list or ledger is empty, explain plainly what is missing
/// and provide a clear way to create or trigger it.
class PieEmptyState extends StatelessWidget {
  const PieEmptyState({
    super.key,
    required this.title,
    String description = '',
    String? subtitle,
    this.icon = Icons.inbox_outlined,
    this.actionLabel,
    this.onAction,
    this.accentColor,
  }) : description = subtitle ?? description;

  final String title;
  final String description;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: PieColors.surface2,
                shape: BoxShape.circle,
                border: Border.all(color: PieColors.border, width: 1),
              ),
              child: Icon(
                icon,
                size: 26,
                color: accentColor ?? PieColors.inkMuted,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: PieTypography.subheading.copyWith(fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Text(
                description,
                style: PieTypography.body.copyWith(
                  color: PieColors.inkSecondary,
                  fontSize: 13,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              PieButton.primary(
                onPressed: onAction,
                label: actionLabel!,
                accentColor: accentColor,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

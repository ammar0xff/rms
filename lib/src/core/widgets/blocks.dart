import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text.dart';
import 'status.dart';

/// Phase-1 shared blocks for the five role apps.
///
/// Every block is phone-safe by construction and neutral by style — role
/// screens tint through accents, never through forks. Each block below is
/// covered by blocks_test.dart at 390px.
class DialogShell extends StatelessWidget {
  const DialogShell({
    super.key,
    required this.title,
    this.subtitle,
    required this.content,
    this.actions = const [],
  });

  final String title;
  final String? subtitle;

  /// Scrolls internally, so long forms fit a 390px viewport by
  /// construction instead of overflowing it.
  final Widget content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        side: const BorderSide(color: AppColors.borderStrong),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: AppText.h1),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(subtitle!, style: AppText.body),
              ],
              const SizedBox(height: 12),
              content,
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 16),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: actions,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Search field plus filter chips plus one action — the head of every list
/// screen, identical everywhere so operators learn it once.
class ListToolbar extends StatelessWidget {
  const ListToolbar({
    super.key,
    this.hint = 'دوّر…',
    this.onQuery,
    this.filters = const [],
    this.selected = 0,
    this.onFilter,
    this.action,
  });

  final String hint;
  final ValueChanged<String>? onQuery;
  final List<String> filters;
  final int selected;
  final ValueChanged<int>? onFilter;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 44,
                child: TextField(
                  onChanged: onQuery,
                  decoration: InputDecoration(
                    hintText: hint,
                    prefixIcon: const Icon(Icons.search, size: 18),
                    border: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(AppSpacing.radiusMd),
                      borderSide:
                          const BorderSide(color: AppColors.borderStrong),
                    ),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12),
                  ),
                ),
              ),
            ),
            if (action != null) ...[
              const SizedBox(width: 8),
              action!,
            ],
          ],
        ),
        if (filters.isNotEmpty) ...[
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < filters.length; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  ChoiceChip(
                    label: Text(filters[i]),
                    selected: i == selected,
                    onSelected: (_) => onFilter?.call(i),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// A section that folds: header row toggles the body. Explainers and
/// policies hide behind these on phones instead of pushing actions down.
class Collapsible extends StatefulWidget {
  const Collapsible({
    super.key,
    required this.title,
    required this.child,
    this.initiallyOpen = false,
  });

  final String title;
  final Widget child;
  final bool initiallyOpen;

  @override
  State<Collapsible> createState() => _CollapsibleState();
}

class _CollapsibleState extends State<Collapsible> {
  late bool _open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(widget.title, style: AppText.bodyStrong),
                ),
                Icon(
                  _open
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: 18,
                  color: AppColors.fgMuted,
                ),
              ],
            ),
          ),
        ),
        if (_open) ...[
          const SizedBox(height: 4),
          widget.child,
        ],
      ],
    );
  }
}

/// One timeline entry: a tone dot on a rail, title, subtitle, trailing.
class TimelineEntry {
  const TimelineEntry({
    required this.tone,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final StatusTone tone;
  final String title;
  final String? subtitle;
  final Widget? trailing;
}

/// A vertical event rail: driver queue, branch history, audit tails.
class TimelineList extends StatelessWidget {
  const TimelineList({super.key, required this.entries});

  final List<TimelineEntry> entries;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < entries.length; i++)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 20,
                child: Column(
                  children: [
                    const SizedBox(height: 4),
                    StatusDot(tone: entries[i].tone),
                    if (i != entries.length - 1)
                      Container(
                        width: 2,
                        height: 28,
                        color: AppColors.borderStrong,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                      bottom: i == entries.length - 1 ? 0 : 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(entries[i].title,
                                style: AppText.tableCellPrimary),
                            if (entries[i].subtitle != null) ...[
                              const SizedBox(height: 2),
                              Text(entries[i].subtitle!,
                                  style: AppText.caption),
                            ],
                          ],
                        ),
                      ),
                      if (entries[i].trailing != null) ...[
                        const SizedBox(width: 8),
                        entries[i].trailing!,
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

/// A pulsing placeholder with the shape of what's coming. Skeletons match
/// their content's layout; spinners are for actions, never for pages.
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({super.key, this.width, this.height = 14});

  final double? width;
  final double height;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.35, end: 0.7).animate(_pulse),
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: AppColors.hover,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        ),
      ),
    );
  }
}

/// Horizontal proportion bars: cash/card split, station load, mix rows.
class MixEntry {
  const MixEntry(
      {required this.label, required this.value, required this.color});

  final String label;
  final double value;
  final Color color;
}

class MixBars extends StatelessWidget {
  const MixBars({super.key, required this.entries});

  final List<MixEntry> entries;

  @override
  Widget build(BuildContext context) {
    final maxV =
        entries.isEmpty ? 1.0 : entries.map((e) => e.value).reduce((a, b) => a > b ? a : b);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final e in entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 72,
                  child: Text(e.label,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 10,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: FractionallySizedBox(
                        widthFactor:
                            maxV <= 0 ? 0 : (e.value / maxV).clamp(0.02, 1.0),
                        child: Container(
                          decoration: BoxDecoration(
                            color: e.color,
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Isolates a numeral from the surrounding Arabic run.
///
/// The design requires it: "Monospace numbers remain strictly left-to-right
/// (`direction: ltr; unicode-bidi: isolate`) within RTL layouts to prevent
/// broken formatting in negative currency deltas or time formats (`MM:SS`)."
/// Flutter's [TextStyle] has no direction parameter, so the bidi isolate is
/// built out of a [Directionality] instead.
class LtrIsolate extends StatelessWidget {
  const LtrIsolate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Directionality(textDirection: TextDirection.ltr, child: child);
  }
}

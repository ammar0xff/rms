import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/primitives.dart';
import '../../core/widgets/status.dart';
import '../../core/widgets/surface_card.dart';
import '../../domain/update/update_prompt_mode.dart';
import '../../domain/update/update_prompt_state.dart';
import 'update_controller.dart';

/// Presents the update to the operator.
///
/// Severity decides the form, and nothing can change that: a mandatory release
/// gets a blocking screen with no dismiss affordance, while an optional or
/// recommended one is a dialog the operator can close. That asymmetry is the
/// point of a mandatory release.
class UpdatePrompt extends StatelessWidget {
  const UpdatePrompt({
    super.key,
    required this.controller,
    this.onDismissed,
  });

  final UpdateController controller;

  /// Called after the operator closes an optional prompt.
  final VoidCallback? onDismissed;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final state = controller.state;
        return switch (state.mode) {
          UpdatePromptMode.none => const SizedBox.shrink(),
          UpdatePromptMode.dismissible => _OptionalPrompt(
              state: state,
              controller: controller,
              onDismissed: onDismissed,
            ),
          _ => UpdateRequiredScreen(
              state: state,
              controller: controller,
              onDismissed: onDismissed,
            ),
        };
      },
    );
  }
}

/// Blocking presentation for a mandatory release, an update in flight, or a
/// failed attempt.
///
/// Rendered above the app rather than inside it: an operator who must update
/// has no work to do until they do.
class UpdateRequiredScreen extends StatelessWidget {
  const UpdateRequiredScreen({
    super.key,
    required this.state,
    required this.controller,
    this.onDismissed,
  });

  final UpdatePromptState state;
  final UpdateController controller;
  final VoidCallback? onDismissed;

  @override
  Widget build(BuildContext context) {
    final release = state.release;
    final tone = switch (state.mode) {
      UpdatePromptMode.failed => StatusTone.negative,
      UpdatePromptMode.completed => StatusTone.positive,
      UpdatePromptMode.working => StatusTone.info,
      _ => StatusTone.warning,
    };
    final color = toneColor(tone);
    final dismissible = !state.mode.isEnforced;

    return PopScope(
      // A mandatory update must not be left with the back gesture either.
      canPop: dismissible,
      child: ColoredBox(
        color: AppColors.base,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: SurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Icon(_iconFor(state.mode), size: 18, color: color),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            state.headline,
                            style: AppText.bodyStrong.copyWith(color: color),
                          ),
                        ),
                        Tag(
                          label: state.mode.label,
                          tone: tone,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    if (release != null) ...[
                      KeyValue(label: 'الإصدار', value: release.version),
                      KeyValue(
                        label: 'رقم البناء',
                        value: '${release.buildNumber}',
                      ),
                      KeyValue(
                        label: 'الأولوية',
                        value: release.severity.label,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                    Text(
                      _bodyFor(state),
                      style: AppText.caption,
                    ),
                    if (state.detail.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.08),
                          borderRadius:
                              BorderRadius.circular(AppSpacing.radiusSm),
                        ),
                        child: Text(state.detail, style: AppText.caption),
                      ),
                    ],
                    if (state.mode == UpdatePromptMode.working) ...[
                      const SizedBox(height: AppSpacing.md),
                      _Progress(progress: state.progress, color: color),
                    ],
                    const SizedBox(height: AppSpacing.lg),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (dismissible && onDismissed != null) ...[
                          RmsButton(
                            label: 'لاحقًا',
                            variant: BtnVariant.ghost,
                            onPressed: onDismissed,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                        ],
                        RmsButton(
                          label: state.actionLabel,
                          variant: BtnVariant.primary,
                          onPressed: state.canApply
                              ? () => controller.apply()
                              : null,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static IconData _iconFor(UpdatePromptMode mode) => switch (mode) {
        UpdatePromptMode.failed => Icons.error_outline,
        UpdatePromptMode.completed => Icons.check_circle_outline,
        UpdatePromptMode.working => Icons.downloading,
        _ => Icons.system_update_alt,
      };

  static String _bodyFor(UpdatePromptState state) {
    if (state.mode == UpdatePromptMode.working) {
      return 'يتم تنزيل الحزمة والتحقق من بصمتها قبل التثبيت.';
    }
    if (state.mode == UpdatePromptMode.completed) {
      return 'تم تثبيت الإصدار الجديد بنجاح.';
    }
    if (state.mode == UpdatePromptMode.failed) {
      return 'لم يكتمل التحديث. راجع التفاصيل ثم أعد المحاولة.';
    }
    // Mandatory releases explain why the operator cannot carry on, rather than
    // leaving a blocking screen with no justification.
    return 'هذا الإصدار مطلوب لمتابعة العمل بأمان. تُحفظ أي أعمال محلية غير '
        'متزامنة ولا تُفقد.';
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final pct = (progress.clamp(0.0, 1.0) * 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          child: LinearProgressIndicator(
            value: progress.clamp(0.0, 1.0),
            minHeight: 6,
            color: color,
            backgroundColor: color.withValues(alpha: 0.15),
          ),
        ),
        const SizedBox(height: 6),
        Text('$pct٪', style: AppText.caption),
      ],
    );
  }
}

/// Dismissible presentation for an optional or recommended release.
class _OptionalPrompt extends StatelessWidget {
  const _OptionalPrompt({
    required this.state,
    required this.controller,
    this.onDismissed,
  });

  final UpdatePromptState state;
  final UpdateController controller;
  final VoidCallback? onDismissed;

  @override
  Widget build(BuildContext context) {
    final release = state.release;
    final blocked = state.check?.isBlockedByLocalWork ?? false;

    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.system_update_alt,
                  size: 18,
                  color: AppColors.info,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    state.headline,
                    style: AppText.bodyStrong.copyWith(color: AppColors.info),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            if (release != null) ...[
              KeyValue(label: 'الإصدار', value: release.version),
              const SizedBox(height: AppSpacing.sm),
            ],
            Text(
              blocked
                  ? 'هناك أعمال محلية غير مرفوعة. يجب رفعها قبل تثبيت التحديث حتى '
                      'لا تُفقد.'
                  : 'يمكن تأجيل هذا التحديث. تُحفظ أي أعمال محلية معلّقة.',
              style: AppText.caption,
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                RmsButton(
                  label: 'لاحقًا',
                  variant: BtnVariant.ghost,
                  onPressed: onDismissed,
                ),
                const SizedBox(width: AppSpacing.sm),
                RmsButton(
                  label: state.actionLabel,
                  variant: BtnVariant.primary,
                  onPressed: state.canApply ? () => controller.apply() : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
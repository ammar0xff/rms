import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/pie_colors.dart';
import '../theme/pie_radius.dart';
import '../theme/pie_typography.dart';

/// Top-anchored, non-blocking floating notification toast.
/// Positioned at the top of the viewport to prevent blocking bottom navigation bars,
/// checkout action panels, or keypad inputs across all 4 applications.
abstract final class PieToast {
  static OverlayEntry? _activeEntry;

  static void show(
    BuildContext context,
    String message, {
    bool isError = false,
    bool isSuccess = false,
    IconData? icon,
    Duration duration = const Duration(milliseconds: 2800),
  }) {
    // Dismiss any existing toast first
    _dismiss();

    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) {
      // Fallback for tests or contexts without an Overlay
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger != null) {
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            duration: duration,
            content: Text(message),
          ),
        );
      }
      return;
    }

    final entry = OverlayEntry(
      builder: (ctx) => _PieToastOverlay(
        message: message,
        isError: isError,
        isSuccess: isSuccess,
        icon: icon,
        duration: duration,
        onDismiss: _dismiss,
      ),
    );

    _activeEntry = entry;
    overlay.insert(entry);
  }

  static void _dismiss() {
    if (_activeEntry != null) {
      try {
        _activeEntry?.remove();
      } catch (_) {}
      _activeEntry = null;
    }
  }
}

class _PieToastOverlay extends StatefulWidget {
  const _PieToastOverlay({
    required this.message,
    required this.isError,
    required this.isSuccess,
    this.icon,
    required this.duration,
    required this.onDismiss,
  });

  final String message;
  final bool isError;
  final bool isSuccess;
  final IconData? icon;
  final Duration duration;
  final VoidCallback onDismiss;

  @override
  State<_PieToastOverlay> createState() => _PieToastOverlayState();
}

class _PieToastOverlayState extends State<_PieToastOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
    _fade = CurvedAnimation(parent: _anim, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, -0.6),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic));

    _anim.forward();

    _dismissTimer = Timer(widget.duration, () {
      if (mounted) {
        _dismissWithAnim();
      }
    });
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _dismissTimer = null;
    _anim.dispose();
    super.dispose();
  }

  void _dismissWithAnim() {
    _dismissTimer?.cancel();
    _dismissTimer = null;
    _anim.reverse().then((_) {
      if (mounted) {
        widget.onDismiss();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.paddingOf(context).top;
    final Color bgColor = widget.isError
        ? const Color(0xFF450A0A)
        : (widget.isSuccess ? const Color(0xFF052E16) : const Color(0xFF0F172A));
    final Color borderColor = widget.isError
        ? const Color(0xFFEF4444)
        : (widget.isSuccess ? const Color(0xFF10B981) : PieColors.cashierAccent);
    final Color textColor = widget.isError
        ? const Color(0xFFFCA5A5)
        : (widget.isSuccess ? const Color(0xFF6EE7B7) : Colors.white);
    final IconData icon = widget.icon ??
        (widget.isError
            ? Icons.error_outline_rounded
            : (widget.isSuccess
                ? Icons.check_circle_outline_rounded
                : Icons.info_outline_rounded));

    return Positioned(
      top: topPadding + 10,
      left: 16,
      right: 16,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: FadeTransition(
              opacity: _fade,
              child: SlideTransition(
                position: _slide,
                child: Dismissible(
                  key: const ValueKey('pie_toast_dismissible'),
                  direction: DismissDirection.up,
                  onDismissed: (_) => widget.onDismiss(),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _dismissWithAnim,
                      borderRadius: PieRadius.borderMd,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: bgColor.withValues(alpha: 0.96),
                          borderRadius: PieRadius.borderMd,
                          border: Border.all(color: borderColor.withValues(alpha: 0.8), width: 1.2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.4),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(icon, color: borderColor, size: 22),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                widget.message,
                                style: PieTypography.bodyStrong.copyWith(
                                  color: textColor,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            InkWell(
                              onTap: _dismissWithAnim,
                              child: Icon(
                                Icons.close_rounded,
                                size: 18,
                                color: textColor.withValues(alpha: 0.6),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

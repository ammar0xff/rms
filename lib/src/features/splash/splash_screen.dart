import 'dart:async';
import 'package:flutter/material.dart';

import '../../core/theme/pie_colors.dart';
import '../../core/theme/pie_radius.dart';
import '../../core/theme/pie_typography.dart';

/// Full-featured animated splash screen for PIE Operations.
class SplashScreen extends StatefulWidget {
  const SplashScreen({
    super.key,
    this.onLoaded,
    this.minimumDuration = const Duration(milliseconds: 1200),
  });

  final VoidCallback? onLoaded;
  final Duration minimumDuration;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  String _statusText = 'جاري التحقق من هوية المحطة والمزامنة...';

  @override
  void initState() {
    super.initState();

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );

    _fadeAnimation = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );

    _scheduleTransition();
  }

  void _scheduleTransition() {
    Timer(const Duration(milliseconds: 600), () {
      if (mounted) {
        setState(() {
          _statusText = 'تهيئة قواعد البيانات ومحرك نقاط البيع...';
        });
      }
    });

    Timer(widget.minimumDuration, () {
      if (!mounted) return;
      if (widget.onLoaded != null) {
        widget.onLoaded!();
      }
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: PieColors.canvas,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(flex: 3),

              // Animated Pulsing PIE Logo
              AnimatedBuilder(
                animation: _animController,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _scaleAnimation.value,
                    child: Opacity(
                      opacity: _fadeAnimation.value,
                      child: child,
                    ),
                  );
                },
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: PieColors.surface2,
                    borderRadius: const BorderRadius.all(Radius.circular(28)),
                    border: Border.all(color: PieColors.roleCashier, width: 2.2),
                    boxShadow: [
                      BoxShadow(
                        color: PieColors.roleCashier.withValues(alpha: 0.35),
                        blurRadius: 36,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Text(
                      'π',
                      style: TextStyle(
                        color: PieColors.roleCashier,
                        fontSize: 54,
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),

              // Brand Title & Slogan
              Text(
                'PIE Operations',
                style: PieTypography.h1.copyWith(
                  color: PieColors.textPrimary,
                  letterSpacing: 1.4,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'نظام تشغيل وإدارة المطاعم المتكامل',
                style: PieTypography.body.copyWith(
                  color: PieColors.textSecondary,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: PieColors.surface2,
                  borderRadius: PieRadius.borderSm,
                  border: Border.all(color: PieColors.borderMuted),
                ),
                child: Text(
                  'POS · KDS · Deliveries · Shift · Accounting',
                  style: PieTypography.caption.copyWith(
                    color: PieColors.textMuted,
                    letterSpacing: 0.8,
                  ),
                ),
              ),

              const Spacer(flex: 2),

              // Spinner & Status
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(PieColors.roleCashier),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _statusText,
                style: PieTypography.caption.copyWith(
                  color: PieColors.textSecondary,
                  fontSize: 12,
                ),
              ),

              const Spacer(flex: 3),
            ],
          ),
        ),
      ),
    );
  }
}

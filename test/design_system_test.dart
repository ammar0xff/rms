import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/core/theme/app_colors.dart';
import 'package:rms/src/core/theme/app_spacing.dart';
import 'package:rms/src/core/theme/app_text.dart';
import 'package:rms/src/core/theme/app_theme.dart';

/// Every value asserted here is quoted from the Stitch project's own
/// `designMd`. These tests are the record that the palette came from the
/// design document and not from a hand-reading of the generated HTML — a
/// wrong value here means the app has drifted off the system.
void main() {
  group('depth by tonal stacking', () {
    test('the five levels match the design', () {
      // Level 0 (canvas) -> Level 4 (modals)
      expect(AppColors.base, const Color(0xFF0A0A0C));
      expect(AppColors.surfaceSunken, const Color(0xFF0C0C0E));
      expect(AppColors.surface, const Color(0xFF101012));
      expect(AppColors.surfaceSecondary, const Color(0xFF16161A));
      expect(AppColors.surfaceBright, const Color(0xFF1A1A1E));
      expect(AppColors.surfaceDrawer, const Color(0xFF0E0E10));
    });

    test('each level is genuinely lighter than the one below it', () {
      // The design stacks tone monotonically; a typo that breaks the ladder
      // would flatten the whole surface hierarchy.
      double l(Color c) => c.computeLuminance();
      final ladder = [
        AppColors.base,
        AppColors.surfaceSunken,
        AppColors.surface,
        AppColors.surfaceSecondary,
        AppColors.surfaceBright,
      ];
      for (var i = 1; i < ladder.length; i++) {
        expect(l(ladder[i]), greaterThan(l(ladder[i - 1])),
            reason: 'level $i must sit above level ${i - 1}');
      }
    });

    test('hairlines follow the border and dividers rule', () {
      expect(AppColors.borderStrong, const Color(0xFF1A1A1E));
      expect(AppColors.borderSubtle, const Color(0xFF16161A));
      expect(AppColors.control, const Color(0xFF1E1E22));
    });
  });

  group('typography and ink levels', () {
    test('the five ink steps match', () {
      expect(AppColors.fg, const Color(0xFFFAFAFA));
      expect(AppColors.fgSecondary, const Color(0xFFE4E4E7));
      expect(AppColors.fgMuted, const Color(0xFFA1A1AA));
      expect(AppColors.fgDim, const Color(0xFF71717A));
      expect(AppColors.fgGhost, const Color(0xFF27272A));
    });

    test('ink also descends monotonically', () {
      double l(Color c) => c.computeLuminance();
      final ink = [
        AppColors.fg,
        AppColors.fgSecondary,
        AppColors.fgMuted,
        AppColors.fgDim,
        AppColors.fgGhost,
      ];
      for (var i = 1; i < ink.length; i++) {
        expect(l(ink[i]), lessThan(l(ink[i - 1])),
            reason: 'ink step $i must sit below step ${i - 1}');
      }
    });
  });

  group('role accents', () {
    test('the four surviving roles carry their documented hues', () {
      expect(AppColors.cashierAccent, const Color(0xFFF5A524));
      expect(AppColors.driverAccent, const Color(0xFF60A5FA));
      expect(AppColors.managerAccent, const Color(0xFF34D399));
      expect(AppColors.developerAccent, const Color(0xFFA78BFA));
    });

    test('sync states carry their documented hues', () {
      expect(AppColors.warning, const Color(0xFFFBBF24));
      expect(AppColors.positive, const Color(0xFF34D399));
      expect(AppColors.negative, const Color(0xFFF87171));
      expect(AppColors.info, const Color(0xFF60A5FA));
      expect(AppColors.destructive, const Color(0xFFEF4444));
    });

    test('filled controls know when their ink must be light', () {
      // The violet admin accent is too light to carry the design's dark ink.
      expect(AppColors.isLightAccent(AppColors.developerAccent), isTrue);
      expect(AppColors.isLightAccent(AppColors.managerAccent), isTrue);
      expect(AppColors.isLightAccent(AppColors.driverAccent), isTrue);
      expect(AppColors.isLightAccent(AppColors.cashierAccent), isFalse);
    });
  });

  group('shapes', () {
    test('radii match the shape language', () {
      expect(AppSpacing.radiusSm, 4);
      expect(AppSpacing.radiusMd, 8);
      expect(AppSpacing.radiusLg, 8);
      expect(AppSpacing.radiusXl, 12);
      expect(AppSpacing.radiusPill, 999);
    });

    test('the 4px base step and 44px touch target hold', () {
      expect(AppSpacing.base, 4);
      expect(AppSpacing.touchTarget, 44);
    });
  });

  group('type scale', () {
    test('numerals are mono, per the font architecture rule', () {
      for (final style in [
        AppText.hero,
        AppText.kpiValue,
        AppText.mono,
        AppText.monoSmall,
      ]) {
        expect(style.fontFamily, 'JetBrainsMono');
        expect(style.fontFeatures, contains(FontFeature.tabularFigures()));
      }
    });

    test('labels are mono too — the design puts labels in the mono face', () {
      for (final style in [AppText.label, AppText.tableHeader]) {
        expect(style.fontFamily, 'JetBrainsMono');
      }
    });

    test('headlines and body copy are the sans face', () {
      for (final style in [
        AppText.h1,
        AppText.h2,
        AppText.pageTitle,
        AppText.body,
        AppText.bodyStrong,
        AppText.sectionHeading,
        AppText.tableCell,
        AppText.tableCellPrimary,
        AppText.caption,
        AppText.navItem,
      ]) {
        expect(style.fontFamily, 'IBMPlexSansArabic');
      }
    });

    test('nominal sizes match the design block', () {
      expect(AppText.hero.fontSize, 36);
      expect(AppText.kpiValue.fontSize, 20);
      expect(AppText.mono.fontSize, 14);
      expect(AppText.monoSmall.fontSize, 11);
      expect(AppText.h1.fontSize, 24);
      expect(AppText.h2.fontSize, 16);
      expect(AppText.pageTitle.fontSize, 20);
      expect(AppText.body.fontSize, 13);
      expect(AppText.bodyStrong.fontSize, 15);
      expect(AppText.label.fontSize, 12);
      expect(AppText.caption.fontSize, 12);
    });

    test('arabic leading carries the design\'s 4px expansion', () {
      // body-md is 13/18 nominally; the expansion makes the ratio 22/13.
      expect(AppText.body.height, closeTo(22 / 13, 0.001));
      // body-lg is 15/22; expanded to 26/15.
      expect(AppText.bodyStrong.height, closeTo(26 / 15, 0.001));
    });

    test('every mono style is a fixed-width face the isolate can rely on', () {
      // The left-to-right rule is applied with Directionality at the widget
      // (LtrIsolate); what matters here is that these styles are the mono face
      // and carry tabular figures, so alignment inside the isolate holds.
      for (final style in [AppText.mono, AppText.hero, AppText.monoSmall]) {
        expect(style.fontFamily, 'JetBrainsMono');
        expect(style.fontFeatures, contains(FontFeature.tabularFigures()));
      }
    });
  });

  group('theme wiring', () {
    test('the app is dark and shadow-free', () {
      final theme = AppTheme.dark();
      expect(theme.brightness, Brightness.dark);
      expect(theme.scaffoldBackgroundColor, AppColors.base);
      expect(theme.elevationOverlayEnabled, isFalse);
      expect(AppTheme.light().brightness, Brightness.dark);
    });

    test('the scheme carries the brand amber as primary', () {
      expect(AppTheme.dark().colorScheme.primary, AppColors.brand);
      expect(AppTheme.dark().colorScheme.onPrimary, AppColors.onBrand);
    });
  });
}

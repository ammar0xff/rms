import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rms/src/core/theme/app_colors.dart';
import 'package:rms/src/core/theme/app_spacing.dart';
import 'package:rms/src/core/theme/app_text.dart';
import 'package:rms/src/core/theme/app_theme.dart';
import 'package:rms/src/core/widgets/buttons.dart';

/// These assertions are transcribed from the design files' own token blocks.
/// They exist to stop the palette drifting away from the source: if a colour is
/// "touched up" here, one of these fails and the change has to be justified
/// against the file it came from.
void main() {
  group('Stitch dark palette, verbatim', () {
    test('surfaces match the elevation ladder in the config', () {
      expect(AppColors.surfaceLowest, const Color(0xFF0E0E10));
      expect(AppColors.surfaceLow, const Color(0xFF1B1B1D));
      expect(AppColors.surfaceCard, const Color(0xFF201F21));
      expect(AppColors.surfaceHigh, const Color(0xFF2A2A2C));
      expect(AppColors.surfaceHighest, const Color(0xFF353437));
      expect(AppColors.surfaceVariant, const Color(0xFF353437));
      expect(AppColors.surfaceBright, const Color(0xFF39393B));
    });

    test('the page background is the file\'s #131315', () {
      expect(AppColors.base, const Color(0xFF131315));
      // The files spell the same colour three ways.
      expect(AppColors.surface, AppColors.base);
    });

    test('foreground steps match on-surface / on-surface-variant', () {
      expect(AppColors.fg, const Color(0xFFE5E1E4));
      expect(AppColors.fgSecondary, const Color(0xFFD7C3AE));
      expect(AppColors.fgMuted, const Color(0xFF9F8E7A));
      expect(AppColors.fgDim, AppColors.fgMuted);
      expect(AppColors.outline, const Color(0xFF9F8E7A));
      expect(AppColors.outlineVariant, const Color(0xFF524434));
    });

    test('the amber primary family is intact', () {
      expect(AppColors.brand, const Color(0xFFFFC77F));
      expect(AppColors.brandContainer, const Color(0xFFF5A524));
      expect(AppColors.brandFixed, const Color(0xFFFFDDB5));
      expect(AppColors.brandFixedDim, const Color(0xFFFFB957));
      expect(AppColors.brandHover, const Color(0xFFFFB944));
      expect(AppColors.onBrand, const Color(0xFF462B00));
      expect(AppColors.onBrandContainer, const Color(0xFF643F00));
    });

    test('the mint secondary family is intact', () {
      expect(AppColors.secondary, const Color(0xFF45DFA4));
      expect(AppColors.secondaryContainer, const Color(0xFF00BD85));
      expect(AppColors.secondaryFixed, const Color(0xFF68FCBF));
      expect(AppColors.onSecondary, const Color(0xFF003825));
      expect(AppColors.positive, AppColors.secondary);
    });

    test('the periwinkle tertiary family is intact', () {
      expect(AppColors.tertiary, const Color(0xFFB6D3FF));
      expect(AppColors.tertiaryContainer, const Color(0xFF84B8FF));
      expect(AppColors.tertiaryFixed, const Color(0xFFD4E3FF));
      expect(AppColors.tertiaryFixedDim, const Color(0xFFA4C9FF));
      expect(AppColors.onTertiary, const Color(0xFF00315D));
      expect(AppColors.info, AppColors.tertiaryContainer);
    });

    test('the error family is intact', () {
      expect(AppColors.negative, const Color(0xFFFFB4AB));
      expect(AppColors.negativeContainer, const Color(0xFF93000A));
      expect(AppColors.onNegative, const Color(0xFF690005));
    });

    test('role accents only borrow hues the design already defines', () {
      final allowed = <Color>[
        AppColors.brand,
        AppColors.tertiary,
        AppColors.secondary,
        AppColors.tertiaryFixedDim,
      ];
      expect(allowed, contains(AppColors.cashierAccent));
      expect(allowed, contains(AppColors.driverAccent));
      expect(allowed, contains(AppColors.managerAccent));
      expect(allowed, contains(AppColors.developerAccent));
    });
  });

  group('type scale from the fontSize blocks', () {
    test('numeric-display becomes hero at 36px', () {
      expect(AppText.hero.fontSize, 36);
      expect(AppText.hero.fontWeight, FontWeight.w600);
    });

    test('headline roles carry the file sizes', () {
      expect(AppText.h1.fontSize, 24);
      expect(AppText.h2.fontSize, 16);
      expect(AppText.pageTitle.fontSize, 20);
      expect(AppText.kpiValue.fontSize, 20);
    });

    test('body and label roles carry the file sizes', () {
      expect(AppText.body.fontSize, 13);
      expect(AppText.bodyStrong.fontSize, 15);
      expect(AppText.label.fontSize, 12);
      expect(AppText.caption.fontSize, 11);
      expect(AppText.tableHeader.fontSize, 11);
    });

    test('every style names the design face', () {
      final sans = <TextStyle>[
        AppText.hero, AppText.h1, AppText.h2, AppText.pageTitle,
        AppText.sectionHeading, AppText.body, AppText.bodyStrong,
        AppText.tableCell, AppText.tableCellPrimary, AppText.tableHeader,
        AppText.label, AppText.caption, AppText.kpiValue, AppText.navItem,
      ];
      for (final style in sans) {
        expect(style.fontFamily, 'IBMPlexSansArabic');
      }
      expect(AppText.mono.fontFamily, 'JetBrainsMono');
      expect(AppText.monoSmall.fontFamily, 'JetBrainsMono');
    });

    test('money columns get tabular figures', () {
      expect(AppText.kpiValue.fontFeatures, contains(FontFeature.tabularFigures()));
    });
  });

  group('radii follow the design\'s usage counts', () {
    test('rounded-lg is the workhorse', () {
      expect(AppSpacing.radiusMd, 8);
      expect(AppSpacing.radiusLg, 12);
      expect(AppSpacing.radiusXl, 16);
    });

    test('the header is the design\'s h-16', () {
      expect(AppSpacing.topBarHeight, 64);
    });
  });

  group('theme wiring', () {
    test('the app is dark, with the file\'s scaffold', () {
      final theme = AppTheme.dark();
      expect(theme.brightness, Brightness.dark);
      expect(theme.scaffoldBackgroundColor, AppColors.base);
      expect(theme.colorScheme.primary, AppColors.brand);
      expect(theme.colorScheme.secondary, AppColors.secondary);
      expect(theme.colorScheme.tertiary, AppColors.tertiary);
      expect(theme.colorScheme.error, AppColors.negative);
      expect(theme.colorScheme.onSurface, AppColors.fg);
    });

    test('there is no light variant to fall back to', () {
      expect(AppTheme.light().brightness, Brightness.dark);
    });
  });

  group('buttons follow the design recipe', () {
    Future<Material?> fillOf(WidgetTester tester, BtnVariant variant) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: Center(child: RmsButton(label: 'احفظ', variant: variant)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final materials = tester.widgetList<Material>(find.byType(Material));
      for (final m in materials) {
        if (m.color != null && m.color != Colors.transparent) return m;
      }
      return null;
    }

    testWidgets('primary is bg-primary with on-primary text', (tester) async {
      await fillOf(tester, BtnVariant.primary);
      final ink = tester.widgetList<Material>(find.byType(Material));
      expect(
        ink.any((m) => m.color == AppColors.brand),
        isTrue,
        reason: 'primary must fill with the design\'s brand amber',
      );
    });

    testWidgets('secondary is a surface-container-high fill',
        (tester) async {
      await fillOf(tester, BtnVariant.secondary);
      final ink = tester.widgetList<Material>(find.byType(Material));
      expect(
        ink.any((m) => m.color == AppColors.surfaceHigh),
        isTrue,
        reason: 'secondary must fill with surface-container-high',
      );
    });
  });
}

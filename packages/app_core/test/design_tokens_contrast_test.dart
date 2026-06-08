import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('dark plum semantic surfaces', () {
    test('warmWhite on dark backgrounds meets 4.5:1', () {
      for (final surface in [
        VamoSemanticColors.dark.background,
        VamoSemanticColors.dark.surface,
        VamoSemanticColors.dark.surfaceMuted,
      ]) {
        expect(
          AppColors.contrastRatio(AppColors.warmWhite, surface),
          greaterThanOrEqualTo(4.5),
          reason: 'warmWhite on $surface',
        );
      }
    });

    test('hero gradient runs plum to darker plum', () {
      expect(VamoSemanticColors.dark.heroGradientStart, AppColors.deepPlum);
      expect(VamoSemanticColors.dark.heroGradientEnd, AppColors.plumDarkHeroEnd);
    });
  });

  group('action colors', () {
    test('goLime on ink meets 3:1 for large text', () {
      expect(
        AppColors.contrastRatio(AppColors.goLime, AppColors.ink),
        greaterThanOrEqualTo(3.0),
      );
    });

    test('goLime on dark plum surfaces meets 3:1 for large CTA labels', () {
      for (final surface in [
        VamoSemanticColors.dark.background,
        VamoSemanticColors.dark.surface,
      ]) {
        expect(
          AppColors.contrastRatio(AppColors.goLime, surface),
          greaterThanOrEqualTo(3.0),
          reason: 'goLime on $surface',
        );
      }
    });

    test('goLime with white text fails WCAG — ink is required', () {
      expect(
        AppColors.contrastRatio(AppColors.goLime, Colors.white),
        lessThan(4.5),
      );
    });

    test('jadeTeal on dark plum background meets 3:1 for accents', () {
      expect(
        AppColors.contrastRatio(
          AppColors.jadeTeal,
          VamoSemanticColors.dark.background,
        ),
        greaterThanOrEqualTo(3.0),
      );
    });
  });

  group('light theme tokens', () {
    test('light semantic background is whiter near-white, surface stays white', () {
      expect(VamoSemanticColors.light.background, AppColors.cream);
      expect(AppColors.cream, const Color(0xFFFBFAF7));
      expect(VamoSemanticColors.light.surface, AppColors.surface);
      expect(VamoSemanticColors.light.surfaceMuted, AppColors.mistGray);
    });
  });

  group('theme preference', () {
    test('appearance toggle maps to ThemeMode', () {
      expect(VamoThemePreference.light.themeMode, ThemeMode.light);
      expect(VamoThemePreference.dark.themeMode, ThemeMode.dark);
      expect(VamoThemePreference.system.themeMode, ThemeMode.system);
    });
  });
}

import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('goLime on ink meets 3:1 for large text', () {
    expect(
      AppColors.contrastRatio(AppColors.goLime, AppColors.ink),
      greaterThanOrEqualTo(3.0),
    );
  });

  test('goLime with white text fails WCAG — ink is required', () {
    expect(
      AppColors.contrastRatio(AppColors.goLime, Colors.white),
      lessThan(4.5),
    );
  });

  test('coralText on white meets 4.5:1 for body text', () {
    expect(
      AppColors.contrastRatio(AppColors.coralText, AppColors.surface),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      AppColors.contrastRatio(AppColors.coralText, AppColors.warmWhite),
      greaterThanOrEqualTo(4.5),
    );
  });

  test('input decoration labels use ink/graphite not primary lime', () {
    final theme = AppTheme.light;
    expect(theme.inputDecorationTheme.labelStyle?.color, AppColors.graphite);
    expect(theme.inputDecorationTheme.floatingLabelStyle?.color, AppColors.ink);
  });

  test('ColorScheme primary is deepPlum not goLime', () {
    expect(AppTheme.light.colorScheme.primary, AppColors.deepPlum);
    expect(AppTheme.light.colorScheme.primary, isNot(AppColors.goLime));
  });

  test('lime primary buttons use ink foreground in theme', () {
    final style = AppTheme.light.filledButtonTheme.style;
    expect(style?.foregroundColor?.resolve({}), AppColors.ink);
    expect(
      AppTheme.light.floatingActionButtonTheme.foregroundColor,
      AppColors.ink,
    );
  });
}

import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('theme preference switches MaterialApp brightness', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          themePreferenceProvider.overrideWith(
            (ref) => ThemePreferenceController(
              persistence: const NoopThemePreferencePersistence(),
              initialPreference: VamoThemePreference.light,
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: VamoThemePreference.light.themeMode,
          home: Builder(
            builder: (context) {
              return Scaffold(
                backgroundColor: context.vamoColors.background,
                body: const SizedBox.shrink(),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final lightContext = tester.element(find.byType(Scaffold));
    expect(
      Theme.of(lightContext).extension<VamoSemanticColors>()!.background,
      AppColors.cream,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          themePreferenceProvider.overrideWith(
            (ref) => ThemePreferenceController(
              persistence: const NoopThemePreferencePersistence(),
              initialPreference: VamoThemePreference.dark,
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: VamoThemePreference.dark.themeMode,
          home: Builder(
            builder: (context) {
              return Scaffold(
                backgroundColor: context.vamoColors.background,
                body: const SizedBox.shrink(),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final darkContext = tester.element(find.byType(Scaffold));
    expect(
      Theme.of(darkContext).extension<VamoSemanticColors>()!.background,
      AppColors.plumDarkBackground,
    );
    expect(
      Theme.of(darkContext).extension<VamoSemanticColors>()!.background,
      isNot(AppColors.ink),
    );
  });
}

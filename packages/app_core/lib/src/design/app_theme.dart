import 'package:flutter/material.dart';

import 'app_colors.dart';

/// The single source of truth for Vamo's look. Features must theme from here,
/// never hard-code colors or text styles.
abstract final class AppTheme {
  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.sunsetCoral,
      primary: AppColors.deepPlum,
      onPrimary: AppColors.warmWhite,
      secondary: AppColors.jadeTeal,
      onSecondary: AppColors.ink,
      surface: AppColors.surface,
      onSurface: AppColors.ink,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.warmWhite,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.warmWhite,
        foregroundColor: AppColors.ink,
        elevation: 0,
        centerTitle: false,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.goLime,
          foregroundColor: AppColors.ink,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
          ),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.goLime,
        foregroundColor: AppColors.ink,
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.ink,
          minimumSize: const Size.fromHeight(52),
          side: const BorderSide(color: AppColors.graphite),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.mistGray,
        labelStyle: const TextStyle(color: AppColors.graphite),
        floatingLabelStyle: const TextStyle(color: AppColors.ink),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.mistGray,
        selectedColor: AppColors.jadeTeal.withValues(alpha: 0.22),
        labelStyle: const TextStyle(color: AppColors.ink),
        secondaryLabelStyle: const TextStyle(color: AppColors.ink),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return AppColors.graphite.withValues(alpha: 0.5);
            }
            if (states.contains(WidgetState.selected)) {
              return AppColors.ink;
            }
            return AppColors.graphite;
          }),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return AppColors.jadeTeal.withValues(alpha: 0.28);
            }
            return AppColors.mistGray;
          }),
          side: WidgetStateProperty.all(
            const BorderSide(color: AppColors.graphite, width: 0.5),
          ),
        ),
      ),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: AppColors.ink),
        bodyMedium: TextStyle(color: AppColors.ink),
        bodySmall: TextStyle(color: AppColors.graphite),
        titleLarge: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w700),
        titleMedium: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600),
      ),
    );
  }
}

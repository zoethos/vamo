import 'package:flutter/material.dart';

import 'app_motion.dart';
import 'app_radius_elevation.dart';
import 'app_semantic_colors.dart';
import 'app_spacing.dart';
import 'app_type_scale.dart';

/// The single source of truth for Vamo's look. Features must theme from here,
/// never hard-code colors or text styles.
abstract final class AppTheme {
  static ThemeData get light => _build(Brightness.light);

  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final semantic = brightness == Brightness.dark
        ? VamoSemanticColors.dark
        : VamoSemanticColors.light;
    final typeScale = VamoTypeScale.forBrightness(brightness);
    const spacing = VamoSpacing.standard;
    final shape = VamoRadiusElevation.forBrightness(brightness);
    const motion = VamoMotion.standardMotion;

    final scheme = ColorScheme(
      brightness: brightness,
      primary: semantic.primary,
      onPrimary: semantic.onPrimary,
      secondary: semantic.secondary,
      onSecondary: semantic.onSecondary,
      surface: semantic.surface,
      onSurface: semantic.onSurface,
      error: semantic.error,
      onError: semantic.onPrimary,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: semantic.background,
      extensions: [semantic, typeScale, spacing, shape, motion],
      appBarTheme: AppBarTheme(
        backgroundColor: semantic.background,
        foregroundColor: semantic.onBackground,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: typeScale.titleMedium,
      ),
      cardTheme: CardThemeData(
        color: semantic.surface,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: shape.cardBorderRadius,
          side: BorderSide(color: semantic.divider.withValues(alpha: 0.6)),
        ),
        margin: EdgeInsets.zero,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: semantic.onSurfaceMuted,
        textColor: semantic.onSurface,
        tileColor: semantic.surface,
        shape: RoundedRectangleBorder(borderRadius: shape.controlBorderRadius),
        contentPadding: EdgeInsetsDirectional.symmetric(
          horizontal: spacing.x4,
          vertical: spacing.x2,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: semantic.action,
          foregroundColor: semantic.onAction,
          disabledBackgroundColor: semantic.surfaceMuted,
          disabledForegroundColor: semantic.onSurfaceMuted,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: shape.controlBorderRadius),
          textStyle: typeScale.labelLarge.copyWith(color: semantic.onAction),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: semantic.action,
        foregroundColor: semantic.onAction,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: shape.controlBorderRadius),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: semantic.onSurface,
          disabledForegroundColor: semantic.onSurfaceMuted,
          minimumSize: const Size.fromHeight(52),
          side: BorderSide(color: semantic.border),
          shape: RoundedRectangleBorder(borderRadius: shape.controlBorderRadius),
          textStyle: typeScale.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: semantic.secondary,
          disabledForegroundColor: semantic.onSurfaceMuted,
          textStyle: typeScale.labelLarge,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: semantic.surfaceMuted,
        labelStyle: typeScale.bodyMedium.copyWith(color: semantic.onSurfaceMuted),
        floatingLabelStyle:
            typeScale.labelMedium.copyWith(color: semantic.onSurface),
        hintStyle: typeScale.bodyMedium.copyWith(color: semantic.onSurfaceMuted),
        errorStyle: typeScale.bodySmall.copyWith(color: semantic.error),
        border: OutlineInputBorder(
          borderRadius: shape.controlBorderRadius,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: shape.controlBorderRadius,
          borderSide: BorderSide(color: semantic.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: shape.controlBorderRadius,
          borderSide: BorderSide(color: semantic.secondary, width: 1.5),
        ),
        contentPadding: EdgeInsetsDirectional.symmetric(
          horizontal: spacing.x4,
          vertical: spacing.x3,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: semantic.surfaceMuted,
        selectedColor: semantic.secondary.withValues(alpha: 0.22),
        disabledColor: semantic.surfaceMuted.withValues(alpha: 0.5),
        labelStyle: typeScale.labelMedium.copyWith(color: semantic.onSurface),
        secondaryLabelStyle:
            typeScale.labelMedium.copyWith(color: semantic.onSurface),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: shape.chipBorderRadius),
        padding: EdgeInsetsDirectional.symmetric(
          horizontal: spacing.x2,
          vertical: spacing.x1,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return semantic.onSurfaceMuted.withValues(alpha: 0.5);
            }
            if (states.contains(WidgetState.selected)) {
              return semantic.onSurface;
            }
            return semantic.onSurfaceMuted;
          }),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return semantic.secondary.withValues(alpha: 0.28);
            }
            return semantic.surfaceMuted;
          }),
          side: WidgetStateProperty.all(
            BorderSide(color: semantic.border, width: 0.5),
          ),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: shape.controlBorderRadius),
          ),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: semantic.surface,
        modalBackgroundColor: semantic.surface,
        shape: RoundedRectangleBorder(borderRadius: shape.sheetBorderRadius),
        showDragHandle: false,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: semantic.onBackground,
        contentTextStyle: typeScale.bodyMedium.copyWith(
          color: semantic.background,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: shape.controlBorderRadius),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: semantic.primary,
        linearTrackColor: semantic.surfaceMuted,
      ),
      dividerTheme: DividerThemeData(
        color: semantic.divider,
        thickness: 1,
        space: 1,
      ),
      textTheme: typeScale.toTextTheme(),
    );
  }
}

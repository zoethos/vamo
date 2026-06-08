import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Semantic color roles mapped from [AppColors] — read via
/// `Theme.of(context).extension<VamoSemanticColors>()`.
@immutable
class VamoSemanticColors extends ThemeExtension<VamoSemanticColors> {
  const VamoSemanticColors({
    required this.background,
    required this.surface,
    required this.surfaceMuted,
    required this.onBackground,
    required this.onSurface,
    required this.onSurfaceMuted,
    required this.primary,
    required this.onPrimary,
    required this.secondary,
    required this.onSecondary,
    required this.accent,
    required this.onAccent,
    required this.action,
    required this.onAction,
    required this.border,
    required this.divider,
    required this.success,
    required this.warning,
    required this.error,
    required this.info,
    required this.emptyStateIcon,
    required this.heroGradientStart,
    required this.heroGradientEnd,
  });

  final Color background;
  final Color surface;
  final Color surfaceMuted;
  final Color onBackground;
  final Color onSurface;
  final Color onSurfaceMuted;
  final Color primary;
  final Color onPrimary;
  final Color secondary;
  final Color onSecondary;
  final Color accent;
  final Color onAccent;
  final Color action;
  final Color onAction;
  final Color border;
  final Color divider;
  final Color success;
  final Color warning;
  final Color error;
  final Color info;
  final Color emptyStateIcon;
  final Color heroGradientStart;
  final Color heroGradientEnd;

  static const light = VamoSemanticColors(
    background: AppColors.cream,
    surface: AppColors.surface,
    surfaceMuted: AppColors.mistGray,
    onBackground: AppColors.ink,
    onSurface: AppColors.ink,
    onSurfaceMuted: AppColors.graphite,
    primary: AppColors.deepPlum,
    onPrimary: AppColors.warmWhite,
    secondary: AppColors.deepTeal,
    onSecondary: AppColors.ink,
    accent: AppColors.sunsetCoral,
    onAccent: AppColors.warmWhite,
    action: AppColors.goLime,
    onAction: AppColors.ink,
    border: AppColors.graphite,
    divider: AppColors.mistGray,
    success: AppColors.jadeTeal,
    warning: AppColors.mango,
    error: AppColors.coralText,
    info: AppColors.sky,
    emptyStateIcon: AppColors.jadeTeal,
    heroGradientStart: AppColors.sunrise,
    heroGradientEnd: AppColors.deepPlum,
  );

  static const dark = VamoSemanticColors(
    background: AppColors.plumDarkBackground,
    surface: AppColors.plumDarkSurface,
    surfaceMuted: AppColors.plumDarkSurfaceMuted,
    onBackground: AppColors.warmWhite,
    onSurface: AppColors.warmWhite,
    onSurfaceMuted: AppColors.mistGray,
    primary: AppColors.deepPlum,
    onPrimary: AppColors.warmWhite,
    secondary: AppColors.jadeTeal,
    onSecondary: AppColors.ink,
    accent: AppColors.sunsetCoral,
    onAccent: AppColors.warmWhite,
    action: AppColors.goLime,
    onAction: AppColors.ink,
    border: AppColors.plumDarkSurfaceMuted,
    divider: AppColors.plumDarkSurface,
    success: AppColors.jadeTeal,
    warning: AppColors.apricot,
    error: AppColors.sunsetCoral,
    info: AppColors.sky,
    emptyStateIcon: AppColors.jadeTeal,
    heroGradientStart: AppColors.deepPlum,
    heroGradientEnd: AppColors.plumDarkHeroEnd,
  );

  @override
  VamoSemanticColors copyWith({
    Color? background,
    Color? surface,
    Color? surfaceMuted,
    Color? onBackground,
    Color? onSurface,
    Color? onSurfaceMuted,
    Color? primary,
    Color? onPrimary,
    Color? secondary,
    Color? onSecondary,
    Color? accent,
    Color? onAccent,
    Color? action,
    Color? onAction,
    Color? border,
    Color? divider,
    Color? success,
    Color? warning,
    Color? error,
    Color? info,
    Color? emptyStateIcon,
    Color? heroGradientStart,
    Color? heroGradientEnd,
  }) {
    return VamoSemanticColors(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      onBackground: onBackground ?? this.onBackground,
      onSurface: onSurface ?? this.onSurface,
      onSurfaceMuted: onSurfaceMuted ?? this.onSurfaceMuted,
      primary: primary ?? this.primary,
      onPrimary: onPrimary ?? this.onPrimary,
      secondary: secondary ?? this.secondary,
      onSecondary: onSecondary ?? this.onSecondary,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      action: action ?? this.action,
      onAction: onAction ?? this.onAction,
      border: border ?? this.border,
      divider: divider ?? this.divider,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      error: error ?? this.error,
      info: info ?? this.info,
      emptyStateIcon: emptyStateIcon ?? this.emptyStateIcon,
      heroGradientStart: heroGradientStart ?? this.heroGradientStart,
      heroGradientEnd: heroGradientEnd ?? this.heroGradientEnd,
    );
  }

  @override
  VamoSemanticColors lerp(ThemeExtension<VamoSemanticColors>? other, double t) {
    if (other is! VamoSemanticColors) return this;
    Color lerpColor(Color a, Color b) => Color.lerp(a, b, t)!;
    return VamoSemanticColors(
      background: lerpColor(background, other.background),
      surface: lerpColor(surface, other.surface),
      surfaceMuted: lerpColor(surfaceMuted, other.surfaceMuted),
      onBackground: lerpColor(onBackground, other.onBackground),
      onSurface: lerpColor(onSurface, other.onSurface),
      onSurfaceMuted: lerpColor(onSurfaceMuted, other.onSurfaceMuted),
      primary: lerpColor(primary, other.primary),
      onPrimary: lerpColor(onPrimary, other.onPrimary),
      secondary: lerpColor(secondary, other.secondary),
      onSecondary: lerpColor(onSecondary, other.onSecondary),
      accent: lerpColor(accent, other.accent),
      onAccent: lerpColor(onAccent, other.onAccent),
      action: lerpColor(action, other.action),
      onAction: lerpColor(onAction, other.onAction),
      border: lerpColor(border, other.border),
      divider: lerpColor(divider, other.divider),
      success: lerpColor(success, other.success),
      warning: lerpColor(warning, other.warning),
      error: lerpColor(error, other.error),
      info: lerpColor(info, other.info),
      emptyStateIcon: lerpColor(emptyStateIcon, other.emptyStateIcon),
      heroGradientStart: lerpColor(heroGradientStart, other.heroGradientStart),
      heroGradientEnd: lerpColor(heroGradientEnd, other.heroGradientEnd),
    );
  }
}

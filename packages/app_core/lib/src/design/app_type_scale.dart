import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Modular mobile-first type scale — compact hierarchy via weight/spacing.
@immutable
class VamoTypeScale extends ThemeExtension<VamoTypeScale> {
  const VamoTypeScale({
    required this.display,
    required this.headline,
    required this.titleLarge,
    required this.titleMedium,
    required this.titleSmall,
    required this.bodyLarge,
    required this.bodyMedium,
    required this.bodySmall,
    required this.labelLarge,
    required this.labelMedium,
    required this.labelSmall,
    required this.overline,
  });

  final TextStyle display;
  final TextStyle headline;
  final TextStyle titleLarge;
  final TextStyle titleMedium;
  final TextStyle titleSmall;
  final TextStyle bodyLarge;
  final TextStyle bodyMedium;
  final TextStyle bodySmall;
  final TextStyle labelLarge;
  final TextStyle labelMedium;
  final TextStyle labelSmall;
  final TextStyle overline;

  static VamoTypeScale forBrightness(Brightness brightness) {
    final primary = brightness == Brightness.dark
        ? AppColors.warmWhite
        : AppColors.ink;
    final secondary = brightness == Brightness.dark
        ? AppColors.mistGray
        : AppColors.graphite;

    TextStyle base({
      required double size,
      required double height,
      FontWeight weight = FontWeight.w400,
      Color? color,
      double? letterSpacing,
    }) {
      return TextStyle(
        fontSize: size,
        height: height / size,
        fontWeight: weight,
        color: color ?? primary,
        letterSpacing: letterSpacing,
      );
    }

    return VamoTypeScale(
      display: base(size: 32, height: 40, weight: FontWeight.w700),
      headline: base(size: 24, height: 32, weight: FontWeight.w700),
      titleLarge: base(size: 20, height: 28, weight: FontWeight.w700),
      titleMedium: base(size: 18, height: 24, weight: FontWeight.w600),
      titleSmall: base(size: 16, height: 22, weight: FontWeight.w600),
      bodyLarge: base(size: 16, height: 24),
      bodyMedium: base(size: 14, height: 20),
      bodySmall: base(size: 12, height: 16, color: secondary),
      labelLarge: base(size: 14, height: 20, weight: FontWeight.w600),
      labelMedium: base(size: 12, height: 16, weight: FontWeight.w600),
      labelSmall: base(size: 11, height: 14, weight: FontWeight.w600),
      overline: base(
        size: 10,
        height: 14,
        weight: FontWeight.w600,
        letterSpacing: 0.8,
        color: secondary,
      ),
    );
  }

  TextTheme toTextTheme() {
    return TextTheme(
      displayLarge: display,
      headlineMedium: headline,
      titleLarge: titleLarge,
      titleMedium: titleMedium,
      titleSmall: titleSmall,
      bodyLarge: bodyLarge,
      bodyMedium: bodyMedium,
      bodySmall: bodySmall,
      labelLarge: labelLarge,
      labelMedium: labelMedium,
      labelSmall: labelSmall,
    );
  }

  @override
  VamoTypeScale copyWith({
    TextStyle? display,
    TextStyle? headline,
    TextStyle? titleLarge,
    TextStyle? titleMedium,
    TextStyle? titleSmall,
    TextStyle? bodyLarge,
    TextStyle? bodyMedium,
    TextStyle? bodySmall,
    TextStyle? labelLarge,
    TextStyle? labelMedium,
    TextStyle? labelSmall,
    TextStyle? overline,
  }) {
    return VamoTypeScale(
      display: display ?? this.display,
      headline: headline ?? this.headline,
      titleLarge: titleLarge ?? this.titleLarge,
      titleMedium: titleMedium ?? this.titleMedium,
      titleSmall: titleSmall ?? this.titleSmall,
      bodyLarge: bodyLarge ?? this.bodyLarge,
      bodyMedium: bodyMedium ?? this.bodyMedium,
      bodySmall: bodySmall ?? this.bodySmall,
      labelLarge: labelLarge ?? this.labelLarge,
      labelMedium: labelMedium ?? this.labelMedium,
      labelSmall: labelSmall ?? this.labelSmall,
      overline: overline ?? this.overline,
    );
  }

  @override
  VamoTypeScale lerp(ThemeExtension<VamoTypeScale>? other, double t) {
    if (other is! VamoTypeScale) return this;
    TextStyle lerpStyle(TextStyle a, TextStyle b) =>
        TextStyle.lerp(a, b, t) ?? a;
    return VamoTypeScale(
      display: lerpStyle(display, other.display),
      headline: lerpStyle(headline, other.headline),
      titleLarge: lerpStyle(titleLarge, other.titleLarge),
      titleMedium: lerpStyle(titleMedium, other.titleMedium),
      titleSmall: lerpStyle(titleSmall, other.titleSmall),
      bodyLarge: lerpStyle(bodyLarge, other.bodyLarge),
      bodyMedium: lerpStyle(bodyMedium, other.bodyMedium),
      bodySmall: lerpStyle(bodySmall, other.bodySmall),
      labelLarge: lerpStyle(labelLarge, other.labelLarge),
      labelMedium: lerpStyle(labelMedium, other.labelMedium),
      labelSmall: lerpStyle(labelSmall, other.labelSmall),
      overline: lerpStyle(overline, other.overline),
    );
  }
}

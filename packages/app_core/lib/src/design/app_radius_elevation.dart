import 'package:flutter/material.dart';

/// Corner radii and elevation shadows for utility vs hero surfaces.
@immutable
class VamoRadiusElevation extends ThemeExtension<VamoRadiusElevation> {
  const VamoRadiusElevation({
    required this.control,
    required this.card,
    required this.sheet,
    required this.hero,
    required this.chip,
    required this.elevation0,
    required this.elevation1,
    required this.elevation2,
    required this.elevation4,
  });

  final double control;
  final double card;
  final double sheet;
  final double hero;
  final double chip;

  final List<BoxShadow> elevation0;
  final List<BoxShadow> elevation1;
  final List<BoxShadow> elevation2;
  final List<BoxShadow> elevation4;

  BorderRadius get controlBorderRadius => BorderRadius.circular(control);
  BorderRadius get cardBorderRadius => BorderRadius.circular(card);
  BorderRadius get sheetBorderRadius =>
      BorderRadius.vertical(top: Radius.circular(sheet));
  BorderRadius get heroBorderRadius => BorderRadius.circular(hero);
  BorderRadius get chipBorderRadius => BorderRadius.circular(chip);

  static VamoRadiusElevation forBrightness(Brightness brightness) {
    final shadowColor = brightness == Brightness.dark
        ? Colors.black.withValues(alpha: 0.45)
        : Colors.black.withValues(alpha: 0.08);

    BoxShadow shadow(double y, double blur, double spread) => BoxShadow(
          color: shadowColor,
          blurRadius: blur,
          spreadRadius: spread,
          offset: Offset(0, y),
        );

    return VamoRadiusElevation(
      control: 12,
      card: 12,
      sheet: 16,
      hero: 16,
      chip: 20,
      elevation0: const [],
      elevation1: [shadow(1, 3, 0)],
      elevation2: [shadow(2, 6, 0)],
      elevation4: [shadow(4, 12, 0)],
    );
  }

  @override
  VamoRadiusElevation copyWith({
    double? control,
    double? card,
    double? sheet,
    double? hero,
    double? chip,
    List<BoxShadow>? elevation0,
    List<BoxShadow>? elevation1,
    List<BoxShadow>? elevation2,
    List<BoxShadow>? elevation4,
  }) {
    return VamoRadiusElevation(
      control: control ?? this.control,
      card: card ?? this.card,
      sheet: sheet ?? this.sheet,
      hero: hero ?? this.hero,
      chip: chip ?? this.chip,
      elevation0: elevation0 ?? this.elevation0,
      elevation1: elevation1 ?? this.elevation1,
      elevation2: elevation2 ?? this.elevation2,
      elevation4: elevation4 ?? this.elevation4,
    );
  }

  @override
  VamoRadiusElevation lerp(
    ThemeExtension<VamoRadiusElevation>? other,
    double t,
  ) {
    if (other is! VamoRadiusElevation) return this;
    double lerpDouble(double a, double b) => a + (b - a) * t;
    return VamoRadiusElevation(
      control: lerpDouble(control, other.control),
      card: lerpDouble(card, other.card),
      sheet: lerpDouble(sheet, other.sheet),
      hero: lerpDouble(hero, other.hero),
      chip: lerpDouble(chip, other.chip),
      elevation0: elevation0,
      elevation1: elevation1,
      elevation2: elevation2,
      elevation4: elevation4,
    );
  }
}

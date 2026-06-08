import 'package:flutter/material.dart';

/// 4pt spacing grid.
@immutable
class VamoSpacing extends ThemeExtension<VamoSpacing> {
  const VamoSpacing({
    required this.x1,
    required this.x2,
    required this.x3,
    required this.x4,
    required this.x6,
    required this.x8,
    required this.x10,
    required this.x12,
  });

  final double x1;
  final double x2;
  final double x3;
  final double x4;
  final double x6;
  final double x8;
  final double x10;
  final double x12;

  static const standard = VamoSpacing(
    x1: 4,
    x2: 8,
    x3: 12,
    x4: 16,
    x6: 24,
    x8: 32,
    x10: 40,
    x12: 48,
  );

  EdgeInsetsDirectional inset({
    double horizontal = 0,
    double vertical = 0,
  }) =>
      EdgeInsetsDirectional.symmetric(
        horizontal: horizontal,
        vertical: vertical,
      );

  @override
  VamoSpacing copyWith({
    double? x1,
    double? x2,
    double? x3,
    double? x4,
    double? x6,
    double? x8,
    double? x10,
    double? x12,
  }) {
    return VamoSpacing(
      x1: x1 ?? this.x1,
      x2: x2 ?? this.x2,
      x3: x3 ?? this.x3,
      x4: x4 ?? this.x4,
      x6: x6 ?? this.x6,
      x8: x8 ?? this.x8,
      x10: x10 ?? this.x10,
      x12: x12 ?? this.x12,
    );
  }

  @override
  VamoSpacing lerp(ThemeExtension<VamoSpacing>? other, double t) {
    if (other is! VamoSpacing) return this;
    double lerpDouble(double a, double b) => a + (b - a) * t;
    return VamoSpacing(
      x1: lerpDouble(x1, other.x1),
      x2: lerpDouble(x2, other.x2),
      x3: lerpDouble(x3, other.x3),
      x4: lerpDouble(x4, other.x4),
      x6: lerpDouble(x6, other.x6),
      x8: lerpDouble(x8, other.x8),
      x10: lerpDouble(x10, other.x10),
      x12: lerpDouble(x12, other.x12),
    );
  }
}

import 'package:flutter/material.dart';

/// Standard motion durations and curves.
@immutable
class VamoMotion extends ThemeExtension<VamoMotion> {
  const VamoMotion({
    required this.instant,
    required this.standard,
    required this.emphasized,
    required this.standardCurve,
    required this.emphasizedCurve,
    required this.enterCurve,
    required this.exitCurve,
  });

  final Duration instant;
  final Duration standard;
  final Duration emphasized;
  final Curve standardCurve;
  final Curve emphasizedCurve;
  final Curve enterCurve;
  final Curve exitCurve;

  static const standardMotion = VamoMotion(
    instant: Duration(milliseconds: 120),
    standard: Duration(milliseconds: 220),
    emphasized: Duration(milliseconds: 360),
    standardCurve: Curves.easeInOut,
    emphasizedCurve: Curves.easeOutCubic,
    enterCurve: Curves.easeOut,
    exitCurve: Curves.easeIn,
  );

  @override
  VamoMotion copyWith({
    Duration? instant,
    Duration? standard,
    Duration? emphasized,
    Curve? standardCurve,
    Curve? emphasizedCurve,
    Curve? enterCurve,
    Curve? exitCurve,
  }) {
    return VamoMotion(
      instant: instant ?? this.instant,
      standard: standard ?? this.standard,
      emphasized: emphasized ?? this.emphasized,
      standardCurve: standardCurve ?? this.standardCurve,
      emphasizedCurve: emphasizedCurve ?? this.emphasizedCurve,
      enterCurve: enterCurve ?? this.enterCurve,
      exitCurve: exitCurve ?? this.exitCurve,
    );
  }

  @override
  VamoMotion lerp(ThemeExtension<VamoMotion>? other, double t) {
    if (other is! VamoMotion) return this;
    return other;
  }
}

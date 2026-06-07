import 'package:flutter/material.dart';

/// Vamo brand palette — identity pass (docs/DESIGN_BRIEF.md).
abstract final class AppColors {
  static const sunsetCoral = Color(0xFFFF5B4D);
  static const apricot = Color(0xFFFFA766);
  static const deepPlum = Color(0xFF6A2D6F);
  static const indigo = Color(0xFF0F1126);
  static const jadeTeal = Color(0xFF00C2A8);
  static const blush = Color(0xFFFFE6EC);
  /// Filled CTA / FAB background only — **ink foreground required**.
  /// Never use as [ColorScheme.primary] or text/icon/border on light surfaces.
  static const goLime = Color(0xFFC6FF00);
  static const ink = Color(0xFF0C0E16);
  static const graphite = Color(0xFF2A2E3A);
  static const mistGray = Color(0xFFE9ECF2);
  static const warmWhite = Color(0xFFFAFAFB);
  /// Darkened from board coral (#D7402F) to meet 4.5:1 on warmWhite for small text.
  static const coralText = Color(0xFFC43628);
  static const surface = Color(0xFFFFFFFF);

  /// coral→plum, directional (LTR topStart→bottomEnd; mirrors in RTL).
  static const brandGradient = LinearGradient(
    begin: AlignmentDirectional.topStart,
    end: AlignmentDirectional.bottomEnd,
    colors: [sunsetCoral, deepPlum],
  );

  /// Relative luminance contrast ratio (WCAG).
  static double contrastRatio(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final lighter = la > lb ? la : lb;
    final darker = la > lb ? lb : la;
    return (lighter + 0.05) / (darker + 0.05);
  }
}

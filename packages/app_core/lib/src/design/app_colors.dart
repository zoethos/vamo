import 'package:flutter/material.dart';

/// Vamo brand palette — identity pass (docs/DESIGN_BRIEF.md).
abstract final class AppColors {
  static const sunsetCoral = Color(0xFFFF5B4D);
  static const apricot = Color(0xFFFFA766);
  static const deepPlum = Color(0xFF6A2D6F);
  static const indigo = Color(0xFF0F1126);
  /// Deep aubergine scaffold — eyedropped from `Vamo-Dark-Plum` mockup backgrounds.
  static const plumDarkBackground = Color(0xFF12101E);
  /// Card / sheet surface — lighter plum lift on the dark board.
  static const plumDarkSurface = Color(0xFF20192C);
  /// Muted plum for chips, inputs, and secondary panels.
  static const plumDarkSurfaceMuted = Color(0xFF2A2438);
  /// Hero gradient anchor — darker plum than [plumDarkBackground].
  static const plumDarkHeroEnd = Color(0xFF130F1F);
  static const jadeTeal = Color(0xFF00C2A8);
  static const blush = Color(0xFFFFE6EC);
  /// Filled CTA / FAB background only — **ink foreground required**.
  /// Never use as [ColorScheme.primary] or text/icon/border on light surfaces.
  static const goLime = Color(0xFFC6FF00);
  static const ink = Color(0xFF0C0E16);
  static const graphite = Color(0xFF2A2E3A);
  static const mistGray = Color(0xFFE9ECF2);
  /// Medium neutral for uncategorized "Other" slices (S40) — not near-black.
  static const neutralMid = Color(0xFF949AA6);
  static const warmWhite = Color(0xFFFAFAFB);
  /// Light scaffold — whiter near-white (S39); card [surface] stays pure white.
  static const cream = Color(0xFFFBFAF7);
  /// Light accent teal from travel reference board (S29).
  static const deepTeal = Color(0xFF07595C);
  static const sky = Color(0xFF21B7D7);
  static const mango = Color(0xFFFFD166);
  static const sunrise = Color(0xFFFF8A3D);
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

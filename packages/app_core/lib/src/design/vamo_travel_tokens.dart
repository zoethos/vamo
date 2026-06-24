import 'package:flutter/material.dart';

/// Pixel tokens for the advanced-travel and date-scroller mockups.
///
/// These names mirror the design spec so feature widgets do not spread raw
/// color values through the tree.
abstract final class VamoTravelTokens {
  static const ink = Color(0xFF0C0E16);
  static const inkSoft = Color(0xFF2A2E3A);
  static const slate = Color(0xFF6B7280);
  static const mute = Color(0xFF8A93A0);
  static const mute2 = Color(0xFF9AA0AC);
  static const lime = Color(0xFFC6FF00);
  static const plum = Color(0xFF6A2D6F);
  static const coral = Color(0xFFFF5B4D);
  static const jade = Color(0xFF00A892);
  static const jadeBright = Color(0xFF00C2A8);
  static const sky = Color(0xFF21B7D7);
  static const carOrange = Color(0xFFFF8A3D);
  static const surface = Color(0xFFFFFFFF);
  static const appBg = Color(0xFFFAFAFB);
  static const hairline = Color(0xFFECEDF1);
  static const border = Color(0xFFE2E4EA);
  static const borderDash = Color(0xFFD7DAE0);
  static const chipBg = Color(0xFFF1F2F5);
  static const segBg = Color(0xFFEEF0F4);
  static const feasGreenBg = Color(0xFFE2F6EC);
  static const feasGreenBd = Color(0xFFBFE8D2);
  static const feasGreenFg = Color(0xFF1F8F5E);
  static const advancedBg = Color(0xFFFBF7FE);
  static const advancedPillBg = Color(0xFFF1E6F8);
  static const advancedPillBorder = Color(0xFFE6D9EE);
  static const destructive = Color(0xFFD7402F);
  static const addTimesBg = Color(0xFFF7FCFA);
  static const optionalText = Color(0xFFB0B6C0);
  static const chevron = Color(0xFFC4C8D0);

  static Color tint(Color color) => color.withValues(alpha: 0.09);
  static Color rangeTint(Color color) => color.withValues(alpha: 0.12);
}

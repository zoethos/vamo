import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';

/// Visual tokens for a snapshot card theme pack (Slice 12).
class SnapshotThemePack {
  const SnapshotThemePack({
    required this.id,
    required this.label,
    required this.keywords,
    required this.gradient,
    required this.statBackground,
    required this.statPrimary,
    required this.statMuted,
    required this.accent,
    required this.memberBubble,
    required this.memberInitial,
    this.tagline = 'Si va?',
  });

  final String id;
  final String label;

  /// Lowercase substrings matched against destination + trip name.
  final List<String> keywords;
  final List<Color> gradient;
  final Color statBackground;
  final Color statPrimary;
  final Color statMuted;
  final Color accent;
  final Color memberBubble;
  final Color memberInitial;
  final String tagline;
}

/// Built-in theme packs — free for everyone in Wave 1 (Slice 12 / Wave 2 seed).
abstract final class SnapshotThemes {
  static const defaultPack = SnapshotThemePack(
    id: 'default',
    label: 'Vamo',
    keywords: [],
    gradient: [
      AppColors.tealDark,
      AppColors.teal,
      Color(0xFF1A6B6A),
    ],
    statBackground: AppColors.sandLight,
    statPrimary: AppColors.tealDark,
    statMuted: AppColors.muted,
    accent: AppColors.sunset,
    memberBubble: AppColors.sand,
    memberInitial: AppColors.tealDark,
  );

  static const rome = SnapshotThemePack(
    id: 'rome',
    label: 'Rome',
    keywords: [
      'rome',
      'roma',
      'vatican',
      'colosseum',
      'trastevere',
      'pantheon',
      'forum',
      'trevi',
    ],
    gradient: [
      Color(0xFF5C2E1F),
      Color(0xFF8B3A2A),
      Color(0xFF4A3A32),
    ],
    statBackground: Color(0xFFF5E6D3),
    statPrimary: Color(0xFF4A2C2A),
    statMuted: Color(0xFF7A5C52),
    accent: Color(0xFFD4A853),
    memberBubble: Color(0xFFE8C9A0),
    memberInitial: Color(0xFF5C2E1F),
    tagline: 'Andiamo',
  );

  static const coast = SnapshotThemePack(
    id: 'coast',
    label: 'Coast',
    keywords: [
      'amalfi',
      'positano',
      'capri',
      'coast',
      'beach',
      'seaside',
      'mediterranean',
      'sicily',
      'sardinia',
      'ibiza',
      'bali',
    ],
    gradient: [
      Color(0xFF0F4C5C),
      Color(0xFF1E7A8C),
      Color(0xFF2E9AAB),
    ],
    statBackground: Color(0xFFF0F7FA),
    statPrimary: Color(0xFF0F4C5C),
    statMuted: Color(0xFF5A7A82),
    accent: Color(0xFFE9794B),
    memberBubble: Color(0xFFB8E0E8),
    memberInitial: Color(0xFF0F4C5C),
  );

  static const paris = SnapshotThemePack(
    id: 'paris',
    label: 'Paris',
    keywords: [
      'paris',
      'eiffel',
      'louvre',
      'montmartre',
      'seine',
      'marais',
    ],
    gradient: [
      Color(0xFF1F2847),
      Color(0xFF2D4A7A),
      Color(0xFF1A3355),
    ],
    statBackground: Color(0xFFF4F0E8),
    statPrimary: Color(0xFF1F2847),
    statMuted: Color(0xFF5C6478),
    accent: Color(0xFFC9A227),
    memberBubble: Color(0xFFE8DFC8),
    memberInitial: Color(0xFF1F2847),
    tagline: 'On y va',
  );

  /// Ordered most-specific first; [defaultPack] is the fallback.
  static const packs = [rome, coast, paris, defaultPack];

  /// Keyword match on destination + trip name (case-insensitive, diacritic-stripped,
  /// whole-word only).
  static SnapshotThemePack resolve({
    String? destination,
    required String tripName,
  }) {
    final haystack = _normalizeHaystack('${destination ?? ''} $tripName');
    for (final pack in packs) {
      if (pack.id == defaultPack.id) continue;
      for (final keyword in pack.keywords) {
        if (_keywordMatches(haystack, keyword)) return pack;
      }
    }
    return defaultPack;
  }

  static String _normalizeHaystack(String input) {
    var s = input.toLowerCase();
    const replacements = {
      'à': 'a',
      'á': 'a',
      'â': 'a',
      'ä': 'a',
      'ã': 'a',
      'å': 'a',
      'è': 'e',
      'é': 'e',
      'ê': 'e',
      'ë': 'e',
      'ì': 'i',
      'í': 'i',
      'î': 'i',
      'ï': 'i',
      'ò': 'o',
      'ó': 'o',
      'ô': 'o',
      'ö': 'o',
      'õ': 'o',
      'ù': 'u',
      'ú': 'u',
      'û': 'u',
      'ü': 'u',
      'ñ': 'n',
      'ç': 'c',
    };
    for (final entry in replacements.entries) {
      s = s.replaceAll(entry.key, entry.value);
    }
    return s;
  }

  static bool _keywordMatches(String haystack, String keyword) {
    final pattern = RegExp('\\b${RegExp.escape(keyword)}\\b');
    return pattern.hasMatch(haystack);
  }
}

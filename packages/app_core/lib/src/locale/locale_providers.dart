import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_locales.dart';

/// Dev-only locale override for RTL / pseudo-locale QA (T13.2).
enum DevLocaleOverride {
  system,
  rtlArabic,
  pseudoLocale,
}

final devLocaleOverrideProvider =
    StateProvider<DevLocaleOverride>((ref) => DevLocaleOverride.system);

/// English labels for the dev-only locale toggle (settings screen).
abstract final class DevLocaleLabels {
  static const section = 'Developer — locale preview';
  static const system = 'System default';
  static const rtl = 'RTL preview (Arabic layout)';
  static const pseudo = 'Pseudo-locale (long strings)';
}

/// Resolves the active [Locale] from the dev override (null = platform default).
Locale? resolveDevLocale(DevLocaleOverride override) {
  switch (override) {
    case DevLocaleOverride.system:
      return null;
    case DevLocaleOverride.rtlArabic:
      return AppLocales.ar;
    case DevLocaleOverride.pseudoLocale:
      return AppLocales.pseudo;
  }
}

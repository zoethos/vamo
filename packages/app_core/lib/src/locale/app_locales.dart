import 'package:flutter/material.dart';

/// Locales registered with [MaterialApp.supportedLocales] (Slice 13).
abstract final class AppLocales {
  static const en = Locale('en');
  static const it = Locale('it');
  static const ar = Locale('ar');
  static const he = Locale('he');
  static const zh = Locale('zh');
  static const hi = Locale('hi');
  static const ja = Locale('ja');
  static const ru = Locale('ru');

  /// Pseudo-locale for overflow / long-string QA (mirrors Android en-XA intent).
  static const pseudo = Locale('en', 'XA');

  static const supported = [
    en,
    it,
    ar,
    he,
    zh,
    hi,
    ja,
    ru,
    pseudo,
  ];

  static bool isRtl(Locale locale) {
    return locale.languageCode == 'ar' || locale.languageCode == 'he';
  }
}

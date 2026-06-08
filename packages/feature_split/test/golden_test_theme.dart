import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';

/// Theme for golden / script smoke tests — deterministic Noto font stack.
ThemeData goldenTestTheme({Brightness brightness = Brightness.light}) {
  final base = brightness == Brightness.dark ? AppTheme.dark : AppTheme.light;
  const fallbacks = [
    'NotoSansArabic',
    'NotoSansHebrew',
    'NotoSansSC',
    'NotoSansDevanagari',
  ];

  return base.copyWith(
    textTheme: base.textTheme.apply(
      fontFamily: 'NotoSans',
      fontFamilyFallback: fallbacks,
    ),
    primaryTextTheme: base.primaryTextTheme.apply(
      fontFamily: 'NotoSans',
      fontFamilyFallback: fallbacks,
    ),
    appBarTheme: base.appBarTheme.copyWith(
      titleTextStyle: base.appBarTheme.titleTextStyle?.copyWith(
        fontFamily: 'NotoSans',
        fontFamilyFallback: fallbacks,
      ),
    ),
    tabBarTheme: base.tabBarTheme.copyWith(
      labelStyle: base.tabBarTheme.labelStyle?.copyWith(
        fontFamily: 'NotoSans',
        fontFamilyFallback: fallbacks,
      ),
      unselectedLabelStyle:
          base.tabBarTheme.unselectedLabelStyle?.copyWith(
        fontFamily: 'NotoSans',
        fontFamilyFallback: fallbacks,
      ),
    ),
  );
}

TextStyle goldenTestTextStyle({
  double fontSize = 14,
  FontWeight? fontWeight,
  Color? color,
}) {
  return TextStyle(
    fontFamily: 'NotoSans',
    fontFamilyFallback: const [
      'NotoSansArabic',
      'NotoSansHebrew',
      'NotoSansSC',
      'NotoSansDevanagari',
    ],
    fontSize: fontSize,
    fontWeight: fontWeight,
    color: color,
  );
}

import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';

/// Theme for golden / script smoke tests — deterministic Noto font stack.
ThemeData goldenTestTheme() {
  const fallbacks = [
    'NotoSansArabic',
    'NotoSansHebrew',
    'NotoSansSC',
    'NotoSansDevanagari',
  ];

  return AppTheme.light.copyWith(
    textTheme: AppTheme.light.textTheme.apply(
      fontFamily: 'NotoSans',
      fontFamilyFallback: fallbacks,
    ),
    primaryTextTheme: AppTheme.light.primaryTextTheme.apply(
      fontFamily: 'NotoSans',
      fontFamilyFallback: fallbacks,
    ),
    appBarTheme: AppTheme.light.appBarTheme.copyWith(
      titleTextStyle: AppTheme.light.appBarTheme.titleTextStyle?.copyWith(
        fontFamily: 'NotoSans',
        fontFamilyFallback: fallbacks,
      ),
    ),
    tabBarTheme: AppTheme.light.tabBarTheme.copyWith(
      labelStyle: AppTheme.light.tabBarTheme.labelStyle?.copyWith(
        fontFamily: 'NotoSans',
        fontFamilyFallback: fallbacks,
      ),
      unselectedLabelStyle:
          AppTheme.light.tabBarTheme.unselectedLabelStyle?.copyWith(
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

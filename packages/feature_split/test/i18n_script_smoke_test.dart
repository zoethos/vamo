import 'package:feature_split/src/expenses/money_format.dart';
import 'package:feature_split/src/trips/locale_format.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'golden_test_theme.dart';

void main() {
  group('script rendering smoke', () {
    const samples = {
      'ar': 'مرحبا بالعالم',
      'he': 'שלום עולם',
      'zh': '你好世界',
      'hi': 'नमस्ते दुनिया',
      'ja': 'こんにちは世界',
      'ru': 'Привет мир',
    };

    for (final entry in samples.entries) {
      testWidgets('renders ${entry.key} without overflow', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: goldenTestTheme(),
            home: Scaffold(
              body: Center(
                child: Text(
                  entry.value,
                  style: goldenTestTextStyle(fontSize: 24),
                  textDirection: _directionFor(entry.key),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(entry.value), findsOneWidget);
      });
    }
  });

  group('locale-aware formatting', () {
    setUpAll(() async {
      await initializeVamoDateFormatting();
    });

    test('Hindi lakh grouping for one lakh rupees', () {
      final formatted =
          formatMoneyFromCents(10000000, 'INR', locale: 'hi_IN');
      expect(formatted, contains('1,00,000'));
    });

    test('Japanese short date uses locale calendar labels', () {
      final formatted = formatShortDate(
        DateTime(2026, 6, 2),
        locale: 'ja',
      );
      expect(formatted, isNotEmpty);
      expect(formatted, isNot(contains('Invalid')));
    });

    test('Russian short date renders Cyrillic month', () {
      final formatted = formatShortDate(
        DateTime(2026, 6, 2),
        locale: 'ru',
      );
      expect(formatted.toLowerCase(), contains('июн'));
    });

    test('Arabic short date renders without throwing', () {
      final formatted = formatShortDate(
        DateTime(2026, 6, 2),
        locale: 'ar',
      );
      expect(formatted, isNotEmpty);
    });
  });
}

TextDirection _directionFor(String languageCode) {
  return switch (languageCode) {
    'ar' || 'he' => TextDirection.rtl,
    _ => TextDirection.ltr,
  };
}

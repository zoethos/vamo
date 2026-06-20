import 'package:app_core/app_core.dart';
import 'package:feature_split/src/weather/weather_badge.dart';
import 'package:feature_split/src/weather/weather_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'weather_labels_test_support.dart';

void main() {
  testWidgets('WeatherBadge renders bucket icon and temp', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: WeatherBadge(
            preview: const WeatherPreview(
              bucket: ConditionBucket.sunny,
              tempHigh: 24,
            ),
            labels: testWeatherBadgeLabels,
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.wb_sunny_outlined), findsOneWidget);
    expect(find.text('24°'), findsOneWidget);
  });

  testWidgets('WeatherBadge maps each bucket to a distinct icon', (tester) async {
    for (final bucket in ConditionBucket.values) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: WeatherBadge(
              preview: WeatherPreview(bucket: bucket, tempHigh: 10),
              labels: testWeatherBadgeLabels,
            ),
          ),
        ),
      );
      expect(find.byIcon(weatherBucketIcon(bucket)), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}

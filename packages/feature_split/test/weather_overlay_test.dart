import 'package:app_core/app_core.dart';
import 'package:feature_split/src/weather/weather_models.dart';
import 'package:feature_split/src/weather/weather_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('WeatherOverlay renders nothing when disabled', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: WeatherOverlay(
            enabled: false,
            bucket: ConditionBucket.sunny,
          ),
        ),
      ),
    );
    expect(
      find.descendant(
        of: find.byType(WeatherOverlay),
        matching: find.byType(CustomPaint),
      ),
      findsNothing,
    );
  });

  testWidgets('WeatherOverlay renders nothing for unknown bucket', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: WeatherOverlay(
            enabled: true,
            bucket: ConditionBucket.unknown,
          ),
        ),
      ),
    );
    expect(
      find.descendant(
        of: find.byType(WeatherOverlay),
        matching: find.byType(CustomPaint),
      ),
      findsNothing,
    );
  });

  testWidgets('WeatherOverlay paints each animated bucket statically', (
    tester,
  ) async {
    for (final bucket in [
      ConditionBucket.sunny,
      ConditionBucket.cloudy,
      ConditionBucket.rain,
      ConditionBucket.thunderstorm,
      ConditionBucket.snow,
      ConditionBucket.fog,
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Scaffold(
              body: SizedBox(
                width: 320,
                height: 220,
                child: WeatherOverlay(
                  enabled: true,
                  bucket: bucket,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}

import 'package:feature_split/src/weather/weather_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ConditionBucket.parse', () {
    test('maps known buckets', () {
      expect(ConditionBucket.parse('sunny'), ConditionBucket.sunny);
      expect(ConditionBucket.parse('thunderstorm'), ConditionBucket.thunderstorm);
    });

    test('unknown strings map to unknown', () {
      expect(ConditionBucket.parse('hail'), ConditionBucket.unknown);
      expect(ConditionBucket.parse(null), ConditionBucket.unknown);
    });
  });

  group('WeatherPreview.fromFunctionPayload', () {
    test('parses available preview', () {
      final preview = WeatherPreview.fromFunctionPayload({
        'available': true,
        'bucket': 'rain',
        'temp_high': 18.6,
        'temp_low': 12.1,
        'date': '2026-06-08',
      });
      expect(preview, isNotNull);
      expect(preview!.bucket, ConditionBucket.rain);
      expect(preview.tempHigh, 19);
      expect(preview.tempLow, 12);
      expect(preview.date, '2026-06-08');
    });

    test('available false returns null', () {
      expect(
        WeatherPreview.fromFunctionPayload({
          'available': false,
          'reason': 'geocode_failed',
        }),
        isNull,
      );
    });

    test('malformed payload returns null', () {
      expect(WeatherPreview.fromFunctionPayload(null), isNull);
      expect(WeatherPreview.fromFunctionPayload('nope'), isNull);
    });
  });
}

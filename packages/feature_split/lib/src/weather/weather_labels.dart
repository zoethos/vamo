import 'weather_models.dart';

class WeatherBadgeLabels {
  const WeatherBadgeLabels({
    required this.temp,
    required this.semanticSunny,
    required this.semanticCloudy,
    required this.semanticRain,
    required this.semanticThunderstorm,
    required this.semanticSnow,
    required this.semanticFog,
    required this.semanticUnknown,
  });

  final String Function(int celsius) temp;
  final String semanticSunny;
  final String semanticCloudy;
  final String semanticRain;
  final String semanticThunderstorm;
  final String semanticSnow;
  final String semanticFog;
  final String semanticUnknown;

  String semanticLabel(ConditionBucket bucket) => switch (bucket) {
        ConditionBucket.sunny => semanticSunny,
        ConditionBucket.cloudy => semanticCloudy,
        ConditionBucket.rain => semanticRain,
        ConditionBucket.thunderstorm => semanticThunderstorm,
        ConditionBucket.snow => semanticSnow,
        ConditionBucket.fog => semanticFog,
        ConditionBucket.unknown => semanticUnknown,
      };
}

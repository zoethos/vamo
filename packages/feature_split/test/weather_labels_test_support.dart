import 'package:feature_split/src/weather/weather_labels.dart';

final testWeatherBadgeLabels = WeatherBadgeLabels(
  temp: (celsius) => '$celsius°',
  semanticSunny: 'Sunny',
  semanticCloudy: 'Cloudy',
  semanticRain: 'Rain',
  semanticThunderstorm: 'Thunderstorm',
  semanticSnow: 'Snow',
  semanticFog: 'Fog',
  semanticUnknown: 'Weather',
);

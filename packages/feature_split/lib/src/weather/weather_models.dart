/// Provider-agnostic weather preview for H-P0 trip cards.
enum ConditionBucket {
  sunny,
  cloudy,
  rain,
  thunderstorm,
  snow,
  fog,
  unknown;

  static ConditionBucket parse(String? raw) {
    if (raw == null || raw.isEmpty) return ConditionBucket.unknown;
    return ConditionBucket.values.firstWhere(
      (value) => value.name == raw,
      orElse: () => ConditionBucket.unknown,
    );
  }
}

class WeatherPreview {
  const WeatherPreview({
    required this.bucket,
    this.tempHigh,
    this.tempLow,
    this.date,
  });

  final ConditionBucket bucket;
  final int? tempHigh;
  final int? tempLow;
  final String? date;

  /// Parses the weather-forecast edge function JSON body.
  /// Returns null for `available: false`, errors, or malformed payloads.
  static WeatherPreview? fromFunctionPayload(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    if (map['available'] != true) return null;
    return WeatherPreview(
      bucket: ConditionBucket.parse(map['bucket'] as String?),
      tempHigh: _roundTemp(map['temp_high']),
      tempLow: _roundTemp(map['temp_low']),
      date: map['date'] as String?,
    );
  }
}

int? _roundTemp(Object? raw) {
  if (raw == null) return null;
  if (raw is int) return raw;
  if (raw is num) return raw.round();
  return int.tryParse(raw.toString());
}

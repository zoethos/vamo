import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'weather_models.dart';

class _CacheEntry {
  _CacheEntry({required this.preview, required this.fetchedAt});

  final WeatherPreview? preview;
  final DateTime fetchedAt;

  bool isExpired(Duration ttl) => DateTime.now().difference(fetchedAt) > ttl;
}

class WeatherRepository {
  WeatherRepository({required SupabaseClient client}) : _client = client;

  static const cacheTtl = Duration(minutes: 5);

  final SupabaseClient _client;
  final Map<String, _CacheEntry> _cache = {};

  Future<WeatherPreview?> fetchPreview(String tripId) async {
    final cached = _cache[tripId];
    if (cached != null && !cached.isExpired(cacheTtl)) {
      return cached.preview;
    }

    try {
      final response = await _client.functions
          .invoke(
            'weather-forecast',
            body: {'trip_id': tripId},
          )
          .timeout(const Duration(seconds: 8));

      if (response.status != 200) {
        return _remember(tripId, null);
      }

      final preview = WeatherPreview.fromFunctionPayload(response.data);
      return _remember(tripId, preview);
    } catch (error, stackTrace) {
      reportAndLog(
        error,
        stackTrace,
        screen: 'weather',
        action: 'fetch_preview',
        severity: ActionFailureSeverity.degraded,
      );
      return _remember(tripId, null);
    }
  }

  WeatherPreview? _remember(String tripId, WeatherPreview? preview) {
    _cache[tripId] = _CacheEntry(
      preview: preview,
      fetchedAt: DateTime.now(),
    );
    return preview;
  }
}

import 'package:app_core/app_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'weather_models.dart';
import 'weather_repository.dart';

final weatherRepositoryProvider = Provider<WeatherRepository>((ref) {
  return WeatherRepository(client: ref.watch(supabaseClientProvider));
});

final weatherPreviewProvider =
    FutureProvider.family<WeatherPreview?, String>((ref, tripId) {
  return ref.watch(weatherRepositoryProvider).fetchPreview(tripId);
});

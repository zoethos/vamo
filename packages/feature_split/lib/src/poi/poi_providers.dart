import 'package:app_core/app_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'poi_repository.dart';

final poiRepositoryProvider = Provider<PoiRepository>((ref) {
  return PoiRepository(
    client: ref.watch(supabaseClientProvider),
    analytics: ref.watch(analyticsProvider),
  );
});

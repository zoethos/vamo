import 'package:app_core/app_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'poi_models.dart';

class PoiRepository {
  PoiRepository({required SupabaseClient client}) : _client = client;

  final SupabaseClient _client;

  Future<PoiDiscoveryResult?> discoverNearby({
    required String tripId,
    required double lat,
    required double lng,
    String? category,
    int? radius,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'poi-discovery',
        body: {
          'trip_id': tripId,
          'lat': lat,
          'lng': lng,
          if (category != null) 'category': category,
          if (radius != null) 'radius': radius,
        },
      ).timeout(const Duration(seconds: 10));

      if (response.status != 200) return null;
      return PoiDiscoveryResult.fromFunctionPayload(response.data);
    } catch (error, stackTrace) {
      reportAndLog(
        error,
        stackTrace,
        screen: 'plan',
        action: 'discover_pois',
        severity: ActionFailureSeverity.degraded,
      );
      return null;
    }
  }
}

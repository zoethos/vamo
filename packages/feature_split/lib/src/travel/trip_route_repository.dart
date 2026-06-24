import 'package:app_core/app_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'route_draft.dart';
import 'travel_leg.dart';

/// Outcome of a draft-route request. Gating is a normal (non-error) state —
/// the user has used their free drafts; manual planning still works.
sealed class RouteDraftResult {
  const RouteDraftResult();
}

class RouteDraftSuccess extends RouteDraftResult {
  const RouteDraftSuccess(this.draft);
  final RouteDraft draft;
}

class RouteDraftGated extends RouteDraftResult {
  const RouteDraftGated(this.reason);
  final String reason;
}

class RouteDraftUnavailable extends RouteDraftResult {
  const RouteDraftUnavailable(this.reason);
  final String reason;
}

final tripRouteRepositoryProvider = Provider<TripRouteRepository>((ref) {
  return TripRouteRepository(
    client: ref.watch(supabaseClientProvider),
    analytics: ref.watch(analyticsProvider),
  );
});

/// Calls the `draft-trip-route` Edge Function and parses its proposal. Never
/// throws — failures degrade to [RouteDraftUnavailable] so the manual path is
/// always available.
class TripRouteRepository {
  TripRouteRepository({
    required SupabaseClient client,
    required Analytics analytics,
  })  : _client = client,
        _analytics = analytics;

  final SupabaseClient _client;
  final Analytics _analytics;

  Future<RouteDraftResult> draftRoute({
    required String tripId,
    required String destination,
    String? tripStart,
    String? tripEnd,
    required List<TravelMode> modes,
    required List<TravelLeg> legs,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'draft-trip-route',
        body: {
          'trip_id': tripId,
          'destination': destination,
          if (tripStart != null) 'trip_start': tripStart,
          if (tripEnd != null) 'trip_end': tripEnd,
          'modes': [for (final mode in modes) mode.name],
          'legs': [for (final leg in legs) _legToJson(leg)],
        },
      ).timeout(const Duration(seconds: 35));

      if (response.status != 200) {
        return RouteDraftUnavailable('function_http_${response.status}');
      }
      final data = response.data;
      if (data is Map && data['gated'] == true) {
        return RouteDraftGated((data['reason'] ?? 'quota_exceeded').toString());
      }
      if (data is Map && data['ok'] == true) {
        final draft = RouteDraft.fromPayload(data);
        if (draft == null || draft.isEmpty) {
          return const RouteDraftUnavailable('invalid_payload');
        }
        return RouteDraftSuccess(draft);
      }
      final reason = data is Map
          ? (data['reason']?.toString() ?? 'unavailable')
          : 'unavailable';
      return RouteDraftUnavailable(reason);
    } catch (error, stackTrace) {
      reportAndLog(
        error,
        stackTrace,
        screen: 'create_trip',
        action: 'draft_route',
        severity: ActionFailureSeverity.degraded,
        analytics: _analytics,
      );
      return const RouteDraftUnavailable('error');
    }
  }

  Map<String, Object?> _legToJson(TravelLeg leg) {
    final fmt = DateFormat('yyyy-MM-dd');
    return {
      'mode': leg.mode.name,
      'window_start':
          leg.windowStart == null ? null : fmt.format(leg.windowStart!),
      'window_end': leg.windowEnd == null ? null : fmt.format(leg.windowEnd!),
      if (leg.windowStartTime != null) 'window_start_time': leg.windowStartTime,
      if (leg.windowEndTime != null) 'window_end_time': leg.windowEndTime,
      'reach_type': leg.reach.type == ReachType.time ? 'time' : 'distance',
      'reach_value': leg.reach.isUnlimited ? 9999 : leg.reach.value,
    };
  }
}

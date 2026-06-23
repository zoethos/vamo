import 'package:app_core/app_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'poi_models.dart';

class PoiRepository {
  PoiRepository({required SupabaseClient client, Analytics? analytics})
      : _client = client,
        _analytics = analytics;

  final SupabaseClient _client;
  final Analytics? _analytics;

  Future<PoiDiscoveryResult?> discoverNearby({
    required String tripId,
    required double lat,
    required double lng,
    String? query,
    String? category,
    int? radius,
  }) async {
    debugBreadcrumb(
      'request',
      screen: 'plan',
      action: 'discover_pois',
      details: {
        'has_query': query != null && query.trim().isNotEmpty,
        'category': category,
        'radius': radius,
      },
    );
    try {
      final response = await _client.functions.invoke(
        'poi-discovery',
        body: {
          'trip_id': tripId,
          'lat': lat,
          'lng': lng,
          if (query != null && query.trim().isNotEmpty) 'query': query.trim(),
          if (category != null) 'category': category,
          if (radius != null) 'radius': radius,
        },
      ).timeout(const Duration(seconds: 10));

      final result = _parseFunctionResult(
        response,
        action: 'discover_pois',
      );
      debugBreadcrumb(
        'response',
        screen: 'plan',
        action: 'discover_pois',
        details: _resultDetails(response.status, result),
      );
      return result;
    } catch (error, stackTrace) {
      reportAndLog(
        error,
        stackTrace,
        screen: 'plan',
        action: 'discover_pois',
        severity: ActionFailureSeverity.degraded,
        analytics: _analytics,
      );
      return null;
    }
  }

  Future<PoiDiscoveryResult?> searchForTrip({
    required String tripId,
    required String query,
    String? regionBias,
    String? category,
    String? sessionId,
  }) async {
    debugBreadcrumb(
      'request',
      screen: 'plan',
      action: 'search_pois',
      details: {
        'query_length': query.trim().length,
        'has_region_bias': regionBias != null && regionBias.trim().isNotEmpty,
        'category': category,
        'has_session': sessionId != null && sessionId.trim().isNotEmpty,
      },
    );
    try {
      final response = await _client.functions.invoke(
        'poi-discovery',
        body: {
          'trip_id': tripId,
          'mode': 'search',
          'query': query.trim(),
          if (regionBias != null && regionBias.trim().isNotEmpty)
            'regionBias': regionBias.trim(),
          if (category != null) 'category': category,
          if (sessionId != null && sessionId.trim().isNotEmpty)
            'session_id': sessionId.trim(),
        },
      ).timeout(const Duration(seconds: 10));

      final result = _parseFunctionResult(
        response,
        action: 'search_pois',
      );
      debugBreadcrumb(
        'response',
        screen: 'plan',
        action: 'search_pois',
        details: _resultDetails(response.status, result),
      );
      return result;
    } catch (error, stackTrace) {
      reportAndLog(
        error,
        stackTrace,
        screen: 'plan',
        action: 'search_pois',
        severity: ActionFailureSeverity.degraded,
        analytics: _analytics,
      );
      return null;
    }
  }

  PoiDiscoveryResult? _parseFunctionResult(
    FunctionResponse response, {
    required String action,
  }) {
    if (response.status != 200) {
      final reason = 'function_http_${response.status}';
      _reportUnavailable(action, reason);
      return PoiDiscoveryResult.unavailable(reason);
    }
    final result = PoiDiscoveryResult.fromFunctionPayload(response.data);
    if (result == null) {
      _reportUnavailable(action, 'invalid_payload');
      return const PoiDiscoveryResult.unavailable('invalid_payload');
    }
    if (result.unavailable) {
      _reportUnavailable(action, result.reason ?? 'unavailable');
    }
    return result;
  }

  void _reportUnavailable(String action, String reason) {
    final code = _safeReason(reason);
    reportAndLog(
      PostgrestException(
        message: 'poi_discovery_$code',
        code: code,
      ),
      StackTrace.current,
      screen: 'plan',
      action: action,
      severity: ActionFailureSeverity.degraded,
      analytics: _analytics,
    );
  }

  Map<String, Object?> _resultDetails(
    int status,
    PoiDiscoveryResult? result,
  ) {
    return {
      'status': status,
      'gated': result?.gated,
      'unavailable': result?.unavailable,
      'reason': result?.reason,
      'count': result?.pois.length,
    };
  }

  String _safeReason(String raw) {
    final sanitized = raw.trim().toLowerCase().replaceAll(
          RegExp(r'[^a-z0-9_]+'),
          '_',
        );
    if (sanitized.isEmpty) return 'unavailable';
    return sanitized.length > 48 ? sanitized.substring(0, 48) : sanitized;
  }
}

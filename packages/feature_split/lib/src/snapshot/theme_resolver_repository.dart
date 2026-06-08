import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final themeResolverRepositoryProvider =
    Provider<ThemeResolverRepository>((ref) {
  return ThemeResolverRepository(
    client: ref.watch(supabaseClientProvider),
  );
});

class ThemeResolverRepository {
  ThemeResolverRepository({required SupabaseClient client}) : _client = client;

  final SupabaseClient _client;

  Future<void> resolveForTrip({
    required String tripId,
    required String? destination,
  }) async {
    final trimmed = destination?.trim();
    if (trimmed == null || trimmed.isEmpty) return;

    try {
      await _client.functions.invoke(
        'resolve-theme',
        body: {
          'trip_id': tripId,
          'destination': trimmed,
        },
      ).timeout(const Duration(seconds: 6));
    } catch (error, stackTrace) {
      // Theming is a cache/fallback enhancement; trip creation must never wait
      // on provider availability, function deployment, or throttling.
      reportAndLog(
        error,
        stackTrace,
        screen: 'theme',
        action: 'resolve_theme',
        severity: ActionFailureSeverity.degraded,
      );
    }
  }
}

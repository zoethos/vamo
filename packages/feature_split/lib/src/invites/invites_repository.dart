import 'package:app_core/app_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'invite_analytics.dart';
import 'invite_channel.dart';

final invitesRepositoryProvider = Provider<InvitesRepository>((ref) {
  return InvitesRepository(
    client: ref.watch(supabaseClientProvider),
    analytics: ref.watch(analyticsProvider),
  );
});

/// Slice 5 — create invite links and join via `join_trip` RPC.
class InvitesRepository {
  InvitesRepository({
    required SupabaseClient client,
    required Analytics analytics,
  })  : _client = client,
        _analytics = analytics;

  final SupabaseClient _client;
  final Analytics _analytics;

  /// Returns an active invite token for the trip (reuses a non-expired row when possible).
  Future<String> getOrCreateInviteToken(String tripId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('Must be signed in to invite');
    }

    final existingRows = await _client
        .from('invites')
        .select('token')
        .eq('trip_id', tripId)
        .eq('created_by', userId)
        .gt('expires_at', DateTime.now().toUtc().toIso8601String())
        .order('created_at', ascending: false)
        .limit(1);

    final existingList = existingRows as List;
    if (existingList.isNotEmpty) {
      return existingList.first['token'] as String;
    }

    final inserted = await _client
        .from('invites')
        .insert({
          'trip_id': tripId,
          'created_by': userId,
        })
        .select('token')
        .single();

    return inserted['token'] as String;
  }

  /// Calls `join_trip` and returns the trip id. Mid-trip join supported.
  Future<String> joinTrip(
    String token, {
    required InviteChannel channel,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('Must be signed in to join a trip');
    }

    final tripId = await _client.rpc(
      'join_trip',
      params: {'p_token': token},
    );

    final id = tripId as String;

    captureInviteAccepted(
      _analytics,
      tripId: id,
      channel: channel,
    );

    return id;
  }
}

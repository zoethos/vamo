import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Subscribes to Postgres changes for one open trip (Slice 9).
class TripRealtimeSubscriber {
  TripRealtimeSubscriber(this._client);

  final SupabaseClient _client;
  final _channels = <String, RealtimeChannel>{};
  final _debounce = <String, Timer>{};

  void subscribe(String tripId, {required Future<void> Function() onRefresh}) {
    if (_channels.containsKey(tripId)) return;

    void scheduleRefresh() {
      _debounce[tripId]?.cancel();
      _debounce[tripId] = Timer(const Duration(milliseconds: 400), () {
        onRefresh();
      });
    }

    final channel = _client.channel('trip:$tripId');
    for (final table in _tablesWithTripId) {
      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'trip_id',
          value: tripId,
        ),
        callback: (_) => scheduleRefresh(),
      );
    }
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'trips',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'id',
        value: tripId,
      ),
      callback: (_) => scheduleRefresh(),
    );

    channel.subscribe();
    _channels[tripId] = channel;
  }

  void unsubscribe(String tripId) {
    _debounce.remove(tripId)?.cancel();
    final channel = _channels.remove(tripId);
    if (channel != null) {
      _client.removeChannel(channel);
    }
  }

  void dispose() {
    for (final id in _channels.keys.toList()) {
      unsubscribe(id);
    }
  }

  static const _tablesWithTripId = [
    'expenses',
    'settlements',
    'trip_members',
    'trip_notes',
    'trip_photos',
  ];
}

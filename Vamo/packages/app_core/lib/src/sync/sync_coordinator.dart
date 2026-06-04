import 'package:supabase_flutter/supabase_flutter.dart';

import 'sync_worker.dart';

/// Pull remote → Drift, then push outbox. Implemented by feature_split [TripsRepository].
abstract interface class RemoteSyncGateway {
  Future<void> pullAll();
  Future<void> pullTrip(String tripId);
}

/// Orchestrates background sync (Slice 9).
class SyncCoordinator {
  SyncCoordinator({
    required RemoteSyncGateway gateway,
    required SyncWorker worker,
    required SupabaseClient client,
  })  : _gateway = gateway,
        _worker = worker,
        _client = client;

  final RemoteSyncGateway _gateway;
  final SyncWorker _worker;
  final SupabaseClient _client;

  bool _syncing = false;

  Future<void> syncNow() async {
    if (_syncing || _client.auth.currentUser == null) return;
    _syncing = true;
    try {
      await _worker.flush();
      await _gateway.pullAll();
    } finally {
      _syncing = false;
    }
  }

  Future<void> refreshTrip(String tripId) async {
    if (_client.auth.currentUser == null) return;
    await _gateway.pullTrip(tripId);
  }

  Future<void> syncNowAndRefreshTrip(String tripId) async {
    if (_syncing || _client.auth.currentUser == null) return;
    _syncing = true;
    try {
      await _worker.flush();
      await _gateway.pullTrip(tripId);
    } finally {
      _syncing = false;
    }
  }
}

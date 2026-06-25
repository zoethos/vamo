import 'dart:async';
import 'dart:convert';

import 'package:app_core/app_core.dart';
import 'package:drift/native.dart';
import 'package:feature_split/src/trips/trips_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'trips_repository_test_support.dart';

void main() {
  test('createTrip schedules offline refresh without blocking', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final client = await _signedInClient('user-1');
    final offlinePacks = _BlockingOfflinePackService(db);
    addTearDown(offlinePacks.release);
    final rpcPayloads = <Map<String, Object?>>[];
    final repo = buildTestTripsRepository(
      db,
      client: client,
      offlinePacks: offlinePacks,
      createTripRpc: ({required client, required id, required input}) async {
        rpcPayloads.add({
          'p_id': id,
          'p_name': input.name.trim(),
          'p_destination': input.destination?.trim(),
          'p_start_date': input.startDate,
          'p_end_date': input.endDate,
          'p_base_currency': input.baseCurrency,
        });
      },
    );

    final tripId = await repo
        .createTrip(
          const CreateTripInput(
            name: 'Rome',
            destination: 'Pantheon',
            startDate: '2026-07-01',
            endDate: '2026-07-05',
            baseCurrency: 'EUR',
          ),
        )
        .timeout(const Duration(seconds: 2));

    expect(tripId, isNotEmpty);
    await offlinePacks.started.future.timeout(const Duration(seconds: 2));
    expect(offlinePacks.calls.single.tripId, tripId);
    expect(
      offlinePacks.calls.single.trigger,
      OfflinePackRefreshTrigger.tripEdit,
    );
    expect(rpcPayloads.single['p_destination'], 'Pantheon');
  });
}

Future<SupabaseClient> _signedInClient(String userId) async {
  final client = SupabaseClient(
    'http://localhost',
    'anon-key',
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );
  await client.auth.recoverSession(
    jsonEncode({
      'access_token': 'test-access-token',
      'token_type': 'bearer',
      'expires_in': 3600,
      'refresh_token': 'test-refresh-token',
      'user': {
        'id': userId,
        'aud': 'authenticated',
        'created_at': DateTime.utc(2026, 1, 1).toIso8601String(),
        'app_metadata': {},
        'user_metadata': {},
      },
    }),
  );
  return client;
}

class _BlockingOfflinePackService extends TripOfflinePackService {
  _BlockingOfflinePackService(AppDatabase db)
      : super(db: db, syncQueue: SyncQueue(db));

  final started = Completer<void>();
  final _release = Completer<void>();
  final calls = <({String tripId, OfflinePackRefreshTrigger trigger})>[];

  void release() {
    if (!_release.isCompleted) _release.complete();
  }

  @override
  Future<OfflinePackManifest?> refreshEssentialsIfNeeded(
    String tripId, {
    required OfflinePackRefreshTrigger trigger,
  }) async {
    calls.add((tripId: tripId, trigger: trigger));
    if (!started.isCompleted) started.complete();
    await _release.future;
    return null;
  }
}

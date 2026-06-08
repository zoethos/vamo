import 'dart:convert';

import 'package:app_core/app_core.dart';
import 'package:feature_split/src/capture/capture_repository.dart';
import 'package:feature_split/src/expenses/expenses_repository.dart';
import 'package:feature_split/src/plan/plan_repository.dart';
import 'package:feature_split/src/places/places_repository.dart';
import 'package:feature_split/src/settle/settlements_repository.dart';
import 'package:feature_split/src/trips/trips_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase client with a signed-in user for repository integration tests.
Future<SupabaseClient> createSignedInTestClient(String userId) async {
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

/// Builds a fully wired [TripsRepository] against an in-memory [AppDatabase].
TripsRepository buildTestTripsRepository(
  AppDatabase db, {
  SupabaseClient? client,
}) {
  final resolved = client ??
      SupabaseClient(
        'http://localhost',
        'anon-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
  final analytics = DebugAnalytics();
  final queue = SyncQueue(db);
  final syncWorker = SyncWorker(
    queue: queue,
    client: resolved,
    analytics: analytics,
    flushWithoutSession: true,
    testExecute: (_) async {},
  );
  final fxRates = FxRatesClient();
  return TripsRepository(
    db: db,
    client: resolved,
    analytics: analytics,
    expenses: ExpensesRepository(
      db: db,
      client: resolved,
      analytics: analytics,
      fxRates: fxRates,
      syncQueue: queue,
      syncWorker: syncWorker,
    ),
    settlements: SettlementsRepository(
      db: db,
      client: resolved,
      analytics: analytics,
      syncQueue: queue,
      syncWorker: syncWorker,
    ),
    capture: CaptureRepository(
      db: db,
      client: resolved,
      syncQueue: queue,
      syncWorker: syncWorker,
    ),
    places: PlacesRepository(
      db: db,
      client: resolved,
      analytics: analytics,
      syncQueue: queue,
    ),
    plan: PlanRepository(
      db: db,
      client: resolved,
      analytics: analytics,
      syncQueue: queue,
      syncWorker: syncWorker,
    ),
    syncQueue: queue,
  );
}

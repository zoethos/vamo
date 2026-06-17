import 'dart:io';

import 'package:app_core/app_core.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:feature_split/src/capture/capture_repository.dart';
import 'package:feature_split/src/expenses/expenses_repository.dart';
import 'package:feature_split/src/notifications/notifications_repository.dart';
import 'package:feature_split/src/plan/plan_repository.dart';
import 'package:feature_split/src/places/places_repository.dart';
import 'package:feature_split/src/settle/settlements_repository.dart';
import 'package:feature_split/src/trips/featured_trip_card.dart';
import 'package:feature_split/src/trips/trip_visual_backdrop.dart';
import 'package:feature_split/src/trips/trips_models.dart';
import 'package:feature_split/src/trips/trips_providers.dart';
import 'package:feature_split/src/trips/trips_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'trips_list_test_support.dart';

TripsRepository _buildTripsRepository(AppDatabase db) {
  final client = SupabaseClient(
    'http://localhost',
    'anon-key',
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );
  final analytics = DebugAnalytics();
  final queue = SyncQueue(db);
  final syncWorker = SyncWorker(
    queue: queue,
    client: client,
    analytics: analytics,
    flushWithoutSession: true,
    testExecute: (_) async {},
  );
  final fxRates = FxRatesClient();
  return TripsRepository(
    db: db,
    client: client,
    analytics: analytics,
    expenses: ExpensesRepository(
      db: db,
      client: client,
      analytics: analytics,
      fxRates: fxRates,
      syncQueue: queue,
      syncWorker: syncWorker,
    ),
    settlements: SettlementsRepository(
      db: db,
      client: client,
      analytics: analytics,
      syncQueue: queue,
      syncWorker: syncWorker,
    ),
    capture: CaptureRepository(
      db: db,
      client: client,
      syncQueue: queue,
      syncWorker: syncWorker,
    ),
    places: PlacesRepository(
      db: db,
      client: client,
      analytics: analytics,
      syncQueue: queue,
    ),
    plan: PlanRepository(
      db: db,
      client: client,
      analytics: analytics,
      syncQueue: queue,
      syncWorker: syncWorker,
    ),
    syncQueue: queue,
    syncWorker: syncWorker,
    notifications: NotificationsRepository(db: db, client: client),
  );
}

void main() {
  test('watchTripSummaries includes background paths from Drift', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final now = DateTime.utc(2026, 3, 1);

    await db.upsertTrip(
      LocalTripsCompanion(
        id: const Value('trip-bg'),
        name: const Value('Amalfi'),
        ownerId: const Value('owner'),
        baseCurrency: const Value('EUR'),
        backgroundPath: const Value('user/trip-bg/hero.jpg'),
        backgroundLocalPath: const Value('/tmp/card-hero.jpg'),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );

    final repo = _buildTripsRepository(db);
    final summaries = await repo.watchTripSummaries().first;

    expect(summaries, hasLength(1));
    expect(summaries.single.backgroundStoragePath, 'user/trip-bg/hero.jpg');
    expect(summaries.single.backgroundLocalPath, '/tmp/card-hero.jpg');
  });

  test(
    'watchTripSummaries re-emits when background_local_path updates',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final now = DateTime.utc(2026, 3, 1);

      await db.upsertTrip(
        LocalTripsCompanion(
          id: const Value('trip-bg'),
          name: const Value('Amalfi'),
          ownerId: const Value('owner'),
          baseCurrency: const Value('EUR'),
          createdAt: Value(now),
          updatedAt: Value(now),
        ),
      );

      final repo = _buildTripsRepository(db);
      final emissions = <List<TripSummary>>[];
      final sub = repo.watchTripSummaries().listen(emissions.add);
      addTearDown(sub.cancel);
      await Future<void>.delayed(Duration.zero);

      expect(emissions.last.single.backgroundLocalPath, isNull);

      await db.updateTripFields(
        'trip-bg',
        LocalTripsCompanion(
          backgroundLocalPath: const Value('/tmp/updated.jpg'),
          updatedAt: Value(now.add(const Duration(seconds: 1))),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(emissions.last.single.backgroundLocalPath, '/tmp/updated.jpg');
    },
  );

  testWidgets('featured card passes local background into TripVisualBackdrop', (
    tester,
  ) async {
    final fixturePath = p.normalize(
      p.join(Directory.current.path, 'test', 'fixtures', 'hero_bg.png'),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...tripsListTestOverrides([
            TripSummary(
              id: 'trip-bg',
              name: 'Amalfi Coast',
              destination: 'Italy',
              baseCurrency: 'EUR',
              backgroundLocalPath: fixturePath,
            ),
          ]),
          tripCardBackgroundImageProvider(
            'trip-bg',
          ).overrideWith((ref) => fixturePath),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: FeaturedTripCard(
              trip: TripSummary(
                id: 'trip-bg',
                name: 'Amalfi Coast',
                destination: 'Italy',
                baseCurrency: 'EUR',
                backgroundLocalPath: fixturePath,
              ),
              participantsLabel: (count) => '$count travelers',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final backdrop = tester.widget<TripVisualBackdrop>(
      find.byType(TripVisualBackdrop),
    );
    expect(backdrop.backgroundImagePath, fixturePath);
    expect(find.byType(Image), findsOneWidget);
  });
}

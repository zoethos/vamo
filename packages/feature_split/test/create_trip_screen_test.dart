import 'dart:typed_data';

import 'package:app_core/app_core.dart';
import 'package:drift/native.dart';
import 'package:feature_split/src/capture/capture_repository.dart';
import 'package:feature_split/src/expenses/expenses_repository.dart';
import 'package:feature_split/src/notifications/notifications_repository.dart';
import 'package:feature_split/src/plan/plan_repository.dart';
import 'package:feature_split/src/places/places_repository.dart';
import 'package:feature_split/src/settle/settlements_repository.dart';
import 'package:feature_split/src/snapshot/theme_resolver_repository.dart';
import 'package:feature_split/src/travel/travel_leg.dart';
import 'package:feature_split/src/travel/trip_route_repository.dart';
import 'package:feature_split/src/trips/create_trip_labels.dart';
import 'package:feature_split/src/trips/create_trip_screen.dart';
import 'package:feature_split/src/trips/destination_visual_repository.dart';
import 'package:feature_split/src/trips/trips_models.dart';
import 'package:feature_split/src/trips/trips_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'travel_test_support.dart';

const _labels = CreateTripLabels(
  title: 'New trip',
  headline: 'Si va?',
  subtitle: 'Start solo.',
  nameLabel: 'Trip name',
  nameHint: 'Name your trip',
  nameRequired: 'Give your trip a name',
  destinationLabel: 'Destination (optional)',
  destinationHint: 'City, region, or country',
  currencyLabel: 'Base currency',
  startDate: 'Start date',
  endDate: 'End date',
  submit: 'Create',
  endBeforeStart: 'End date must be after start date.',
  clearDate: 'Clear date',
  datePickerCancel: 'Cancel',
  datePickerSkip: 'Skip',
  datePickerSelect: 'Select',
  advanced: advancedTravelTestLabels,
);

const _profile = UserProfile(
  id: 'user-1',
  displayName: 'Tester',
  baseCurrency: 'EUR',
);

void main() {
  testWidgets('new trip form keeps primary inputs clean and readable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          analyticsProvider.overrideWithValue(DebugAnalytics()),
          userProfileProvider.overrideWith((ref) async => _profile),
          supabaseClientProvider.overrideWithValue(_client),
          distanceUnitProvider.overrideWith(
            (ref) => DistanceUnitController(
              persistence: const NoopDistanceUnitPersistence(),
            ),
          ),
        ],
        child: const MaterialApp(
          themeMode: ThemeMode.light,
          home: CreateTripScreen(labels: _labels),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Name your trip'), findsOneWidget);
    expect(find.text('City, region, or country'), findsOneWidget);
    expect(find.text('Amalfi with the crew'), findsNothing);
    expect(find.text('Positano, Italy'), findsNothing);
    expect(find.text('Base currency'), findsNothing);
    expect(find.text('AI resolve'), findsNothing);
    expect(find.text('Find'), findsOneWidget);
    expect(find.text('Multimodal'), findsOneWidget);
    expect(find.byIcon(Icons.edit), findsNothing);
    expect(find.byIcon(Icons.search), findsNothing);

    final fields = tester.widgetList<TextField>(
      find.byType(TextField),
    );
    for (final field in fields.take(2)) {
      final decoration = field.decoration;
      expect(decoration?.filled, isFalse);
      expect(decoration?.fillColor, Colors.transparent);
      expect(decoration?.enabledBorder, InputBorder.none);
      expect(decoration?.focusedBorder, InputBorder.none);
    }
  });

  testWidgets('failed AI draft rolls back the just-created trip', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final trips = _DraftFailureTripsRepository(db);
    final routeDraft = _UnavailableTripRouteRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          analyticsProvider.overrideWithValue(DebugAnalytics()),
          userProfileProvider.overrideWith((ref) async => _profile),
          supabaseClientProvider.overrideWithValue(_client),
          distanceUnitProvider.overrideWith(
            (ref) => DistanceUnitController(
              persistence: const NoopDistanceUnitPersistence(),
            ),
          ),
          tripsRepositoryProvider.overrideWith((ref) => trips),
          tripRouteRepositoryProvider.overrideWith((ref) => routeDraft),
        ],
        child: const MaterialApp(
          themeMode: ThemeMode.light,
          home: CreateTripScreen(labels: _labels),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, 'Weekend');
    await tester.tap(find.text('Draft with AI'));
    await tester.pumpAndSettle();

    expect(trips.createdInputs.single.name, 'Weekend');
    expect(routeDraft.requestedTripId, 'trip-1');
    expect(trips.discardedTripIds, ['trip-1']);
    expect(find.text('Could not draft.'), findsOneWidget);
  });

  testWidgets('typed destination resolves background after trip create', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final trips = _DraftFailureTripsRepository(db);
    final routeDraft = _UnavailableTripRouteRepository();
    final visuals = _RecordingDestinationVisualRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          analyticsProvider.overrideWithValue(DebugAnalytics()),
          userProfileProvider.overrideWith((ref) async => _profile),
          supabaseClientProvider.overrideWithValue(_client),
          distanceUnitProvider.overrideWith(
            (ref) => DistanceUnitController(
              persistence: const NoopDistanceUnitPersistence(),
            ),
          ),
          tripsRepositoryProvider.overrideWith((ref) => trips),
          tripRouteRepositoryProvider.overrideWith((ref) => routeDraft),
          destinationVisualRepositoryProvider.overrideWith((ref) => visuals),
          themeResolverRepositoryProvider.overrideWith(
            (ref) => _NoopThemeResolverRepository(),
          ),
        ],
        child: const MaterialApp(
          themeMode: ThemeMode.light,
          home: CreateTripScreen(labels: _labels),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Paris weekend');
    await tester.enterText(fields.at(1), 'Eiffel Tower');
    await tester.tap(find.text('Draft with AI'));
    await tester.pumpAndSettle();

    expect(trips.createdInputs.single.destination, 'Eiffel Tower');
    expect(visuals.calls.single.destination, 'Eiffel Tower');
    expect(visuals.calls.single.tripId, 'trip-1');
    expect(visuals.calls.single.observationKind, 'create_trip_background');
    expect(trips.backgroundBytes.single.tripId, 'trip-1');
    expect(
        trips.backgroundBytes.single.sourceName, 'destination-foursquare.jpg');
    expect(trips.backgroundBytes.single.bytes, [7, 8, 9]);
  });
}

class _DraftFailureTripsRepository extends TripsRepository {
  _DraftFailureTripsRepository(AppDatabase db)
      : super(
          db: db,
          client: _client,
          analytics: _analytics,
          expenses: ExpensesRepository(
            db: db,
            client: _client,
            analytics: _analytics,
            fxRates: FxRatesClient(),
            syncQueue: _queue(db),
            syncWorker: _syncWorker(db),
          ),
          settlements: SettlementsRepository(
            db: db,
            client: _client,
            analytics: _analytics,
            syncQueue: _queue(db),
            syncWorker: _syncWorker(db),
          ),
          capture: CaptureRepository(
            db: db,
            client: _client,
            syncQueue: _queue(db),
            syncWorker: _syncWorker(db),
            tagCaptureLocation: false,
          ),
          places: PlacesRepository(
            db: db,
            client: _client,
            analytics: _analytics,
            syncQueue: _queue(db),
          ),
          plan: PlanRepository(
            db: db,
            client: _client,
            analytics: _analytics,
            syncQueue: _queue(db),
            syncWorker: _syncWorker(db),
          ),
          syncQueue: _queue(db),
          syncWorker: _syncWorker(db),
          notifications: NotificationsRepository(db: db, client: _client),
        );

  final createdInputs = <CreateTripInput>[];
  final discardedTripIds = <String>[];
  final backgroundBytes = <_BackgroundBytesCall>[];

  @override
  Future<String> createTrip(CreateTripInput input) async {
    createdInputs.add(input);
    return 'trip-1';
  }

  @override
  Future<void> discardNewTripAfterDraftFailure(String tripId) async {
    discardedTripIds.add(tripId);
  }

  @override
  Future<void> setTripBackgroundBytes({
    required String tripId,
    required String sourceName,
    required Uint8List bytes,
  }) async {
    backgroundBytes.add(
      _BackgroundBytesCall(
        tripId: tripId,
        sourceName: sourceName,
        bytes: bytes.toList(growable: false),
      ),
    );
  }
}

class _RecordingDestinationVisualRepository
    extends DestinationVisualRepository {
  _RecordingDestinationVisualRepository()
      : super(client: _client, analytics: _analytics);

  final calls = <_DestinationVisualCall>[];

  @override
  Future<DestinationVisual?> resolve({
    required String destination,
    double? lat,
    double? lng,
    String? tripId,
    String? observationKind,
  }) async {
    calls.add(
      _DestinationVisualCall(
        destination: destination,
        tripId: tripId,
        observationKind: observationKind,
      ),
    );
    return DestinationVisual(
      source: 'foursquare',
      imageBytes: Uint8List.fromList([7, 8, 9]),
      mimeType: 'image/jpeg',
      title: destination,
    );
  }
}

class _NoopThemeResolverRepository extends ThemeResolverRepository {
  _NoopThemeResolverRepository() : super(client: _client);

  @override
  Future<void> resolveForTrip({
    required String tripId,
    required String? destination,
  }) async {}
}

class _DestinationVisualCall {
  const _DestinationVisualCall({
    required this.destination,
    required this.tripId,
    required this.observationKind,
  });

  final String destination;
  final String? tripId;
  final String? observationKind;
}

class _BackgroundBytesCall {
  const _BackgroundBytesCall({
    required this.tripId,
    required this.sourceName,
    required this.bytes,
  });

  final String tripId;
  final String sourceName;
  final List<int> bytes;
}

class _UnavailableTripRouteRepository extends TripRouteRepository {
  _UnavailableTripRouteRepository()
      : super(client: _client, analytics: _analytics);

  String? requestedTripId;

  @override
  Future<RouteDraftResult> draftRoute({
    required String tripId,
    required String destination,
    String? tripStart,
    String? tripEnd,
    required List<TravelMode> modes,
    required List<TravelLeg> legs,
  }) async {
    requestedTripId = tripId;
    return const RouteDraftUnavailable('test');
  }
}

final _client = SupabaseClient(
  'http://localhost',
  'anon-key',
  authOptions: const AuthClientOptions(autoRefreshToken: false),
);
final _analytics = DebugAnalytics();
final _queues = <AppDatabase, SyncQueue>{};
final _workers = <AppDatabase, SyncWorker>{};

SyncQueue _queue(AppDatabase db) =>
    _queues.putIfAbsent(db, () => SyncQueue(db));

SyncWorker _syncWorker(AppDatabase db) => _workers.putIfAbsent(
      db,
      () => SyncWorker(
        queue: _queue(db),
        client: _client,
        analytics: _analytics,
        flushWithoutSession: true,
        testExecute: (_) async {},
      ),
    );

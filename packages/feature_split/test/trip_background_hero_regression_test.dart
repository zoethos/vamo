import 'dart:async';
import 'dart:io';

import 'package:app_core/app_core.dart';
import 'package:drift/drift.dart' hide Column, isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:feature_split/src/capture/capture_action_sheet.dart';
import 'package:feature_split/src/trips/trip_visual_backdrop.dart';
import 'package:feature_split/src/trips/trips_providers.dart';
import 'package:feature_split/src/trips/trips_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'trips_repository_test_support.dart';

class _RecordingAnalytics implements Analytics {
  _RecordingAnalytics(this.events);

  final List<Map<String, Object?>> events;

  @override
  void capture(VamoEvent event, {Map<String, Object?> properties = const {}}) {
    events.add({'event': event, 'properties': properties});
  }

  @override
  Future<void> identify(String userId) async {}

  @override
  Future<void> reset() async {}
}

class _StubAuthRepository extends AuthRepository {
  _StubAuthRepository(this._user) : super(_client());

  static SupabaseClient _client() => SupabaseClient(
        'http://localhost',
        'anon-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );

  final User _user;

  @override
  User? get currentUser => _user;

  @override
  bool get isSignedIn => true;

  @override
  Stream<AuthState> get authStateChanges => const Stream.empty();
}

class _SheetHost extends StatefulWidget {
  const _SheetHost({
    required this.tripId,
    required this.fixturePath,
    required this.onDismissed,
    required this.container,
  });

  final String tripId;
  final String fixturePath;
  final VoidCallback onDismissed;
  final ProviderContainer container;

  @override
  State<_SheetHost> createState() => _SheetHostState();
}

class _SheetHostState extends State<_SheetHost> {
  var _open = true;

  @override
  Widget build(BuildContext context) {
    if (!_open) return const SizedBox.shrink();
    return CaptureChoiceSheet(
      tripId: widget.tripId,
      navigationContext: context,
      providerContainer: widget.container,
      onDismiss: () async {
        setState(() => _open = false);
        widget.onDismissed();
      },
      pickImage: ({
        required source,
        maxWidth,
        maxHeight,
        imageQuality,
      }) async {
        return XFile(widget.fixturePath);
      },
    );
  }
}

class _E2EHost extends StatefulWidget {
  const _E2EHost({
    required this.tripId,
    required this.fixturePath,
    required this.onDismissed,
    required this.container,
  });

  final String tripId;
  final String fixturePath;
  final VoidCallback onDismissed;
  final ProviderContainer container;

  @override
  State<_E2EHost> createState() => _E2EHostState();
}

class _E2EHostState extends State<_E2EHost> {
  var _sheetOpen = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          _HeroProbe(tripId: widget.tripId),
          if (_sheetOpen)
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: CaptureChoiceSheet(
                  tripId: widget.tripId,
                  navigationContext: context,
                  providerContainer: widget.container,
                  onDismiss: () async {
                    setState(() => _sheetOpen = false);
                    widget.onDismissed();
                  },
                  pickImage: ({
                    required source,
                    maxWidth,
                    maxHeight,
                    imageQuality,
                  }) async {
                    return XFile(widget.fixturePath);
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DisposeDuringPickHost extends StatefulWidget {
  const _DisposeDuringPickHost({
    super.key,
    required this.tripId,
    required this.fixturePath,
    required this.container,
    required this.pickCompleter,
  });

  final String tripId;
  final String fixturePath;
  final ProviderContainer container;
  final Completer<XFile> pickCompleter;

  @override
  State<_DisposeDuringPickHost> createState() => _DisposeDuringPickHostState();
}

class _DisposeDuringPickHostState extends State<_DisposeDuringPickHost> {
  var _sheetOpen = true;

  void closeSheet() => setState(() => _sheetOpen = false);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          _HeroProbe(tripId: widget.tripId),
          if (_sheetOpen)
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: CaptureChoiceSheet(
                  tripId: widget.tripId,
                  navigationContext: context,
                  providerContainer: widget.container,
                  onDismiss: () async {
                    setState(() => _sheetOpen = false);
                  },
                  pickImage: ({
                    required source,
                    maxWidth,
                    maxHeight,
                    imageQuality,
                  }) {
                    return widget.pickCompleter.future;
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _HeroProbe extends ConsumerWidget {
  const _HeroProbe({required this.tripId});

  final String tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = ref.watch(tripHeroBackgroundProvider(tripId));
    return TripVisualBackdrop(
      tripName: 'Regression trip',
      backgroundImagePath: path,
      child: const SizedBox(height: 220),
    );
  }
}

Future<void> _selectBackground(WidgetTester tester) async {
  final wheel = find.byType(ListWheelScrollView);
  await tester.drag(wheel, const Offset(0, -240));
  await tester.pumpAndSettle();
  expect(find.text('Background'), findsOneWidget);
  await tester.tapAt(tester.getCenter(find.byType(CaptureChoiceSheet)));
}

Future<String?> _readBackgroundLocalPath(AppDatabase db, String tripId) async {
  final row = await (db.select(db.localTrips)
        ..where((t) => t.id.equals(tripId)))
      .getSingleOrNull();
  return row?.backgroundLocalPath;
}

void main() {
  const tripId = 'trip-bg-regression';
  const ownerId = 'owner-bg';

  late AppDatabase db;
  late TripsRepository repo;
  late SupabaseClient client;
  late String fixturePath;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    client = await createSignedInTestClient(ownerId);
    repo = buildTestTripsRepository(db, client: client);
    fixturePath = p.normalize(
      p.join(Directory.current.path, 'test', 'fixtures', 'hero_bg.png'),
    );
    expect(File(fixturePath).existsSync(), isTrue);

    final now = DateTime.utc(2026, 6, 5);
    await db.upsertTrip(
      LocalTripsCompanion(
        id: const Value(tripId),
        name: const Value('Regression trip'),
        ownerId: const Value(ownerId),
        baseCurrency: const Value('EUR'),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );
  });

  tearDown(() async {
    await db.close();
  });

  test('setTripBackground persists a local hero path', () async {
    await repo
        .setTripBackground(tripId: tripId, sourcePath: fixturePath)
        .timeout(const Duration(seconds: 2));
    final storedPath = await _readBackgroundLocalPath(db, tripId);
    expect(storedPath, isNotNull);
    expect(File(storedPath!).existsSync(), isTrue);
  });

  testWidgets('background carousel dismisses before repo write completes', (
    tester,
  ) async {
    var dismissed = false;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          supabaseClientProvider.overrideWithValue(client),
          analyticsProvider.overrideWithValue(DebugAnalytics()),
          authRepositoryProvider.overrideWith(
            (ref) => _StubAuthRepository(
              User(
                id: ownerId,
                appMetadata: const {},
                userMetadata: const {},
                aud: 'authenticated',
                createdAt: DateTime.utc(2026, 1, 1).toIso8601String(),
              ),
            ),
          ),
          tripsRepositoryProvider.overrideWith((ref) => repo),
          tripsSyncProvider.overrideWith((ref) async {}),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) => _SheetHost(
              tripId: tripId,
              fixturePath: fixturePath,
              container: ProviderScope.containerOf(context, listen: false),
              onDismissed: () => dismissed = true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _selectBackground(tester);

    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (dismissed) break;
    }
    expect(dismissed, isTrue);
    expect(find.byType(CaptureChoiceSheet), findsNothing);
  });

  testWidgets(
    'background pick dismisses carousel, persists locally, and updates hero',
    (tester) async {
      var dismissed = false;
      final overrides = [
        appDatabaseProvider.overrideWithValue(db),
        supabaseClientProvider.overrideWithValue(client),
        analyticsProvider.overrideWithValue(DebugAnalytics()),
        authRepositoryProvider.overrideWith(
          (ref) => _StubAuthRepository(
            User(
              id: ownerId,
              appMetadata: const {},
              userMetadata: const {},
              aud: 'authenticated',
              createdAt: DateTime.utc(2026, 1, 1).toIso8601String(),
            ),
          ),
        ),
        tripsRepositoryProvider.overrideWith((ref) => repo),
        tripsSyncProvider.overrideWith((ref) async {}),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides,
          child: MaterialApp(
            theme: AppTheme.light,
            home: Builder(
              builder: (context) => _E2EHost(
                tripId: tripId,
                fixturePath: fixturePath,
                container: ProviderScope.containerOf(context, listen: false),
                onDismissed: () => dismissed = true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _selectBackground(tester);

      String? storedPath;
      for (var i = 0; i < 60; i++) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        await tester.pump(const Duration(milliseconds: 50));
        if (dismissed) {
          storedPath = await _readBackgroundLocalPath(db, tripId);
          if (storedPath != null) break;
        }
      }

      expect(dismissed, isTrue);
      expect(find.byType(CaptureChoiceSheet), findsNothing);
      expect(storedPath, isNotNull);
      expect(File(storedPath!).existsSync(), isTrue);

      await tester.pump(const Duration(milliseconds: 100));

      final backdrop = tester.widget<TripVisualBackdrop>(
        find.byType(TripVisualBackdrop),
      );
      expect(backdrop.backgroundImagePath, storedPath);
      expect(find.byType(Image), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 600));
    },
  );

  testWidgets(
    'setTripBackground completes after carousel state disposes during pick',
    (tester) async {
      final pickCompleter = Completer<XFile>();
      final hostKey = GlobalKey<_DisposeDuringPickHostState>();
      final events = <Map<String, Object?>>[];
      final overrides = [
        appDatabaseProvider.overrideWithValue(db),
        supabaseClientProvider.overrideWithValue(client),
        analyticsProvider.overrideWithValue(_RecordingAnalytics(events)),
        authRepositoryProvider.overrideWith(
          (ref) => _StubAuthRepository(
            User(
              id: ownerId,
              appMetadata: const {},
              userMetadata: const {},
              aud: 'authenticated',
              createdAt: DateTime.utc(2026, 1, 1).toIso8601String(),
            ),
          ),
        ),
        tripsRepositoryProvider.overrideWith((ref) => repo),
        tripsSyncProvider.overrideWith((ref) async {}),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides,
          child: MaterialApp(
            theme: AppTheme.light,
            home: Builder(
              builder: (context) => _DisposeDuringPickHost(
                key: hostKey,
                tripId: tripId,
                fixturePath: fixturePath,
                container: ProviderScope.containerOf(context, listen: false),
                pickCompleter: pickCompleter,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _selectBackground(tester);
      await tester.pump();

      hostKey.currentState!.closeSheet();
      await tester.pumpAndSettle();
      expect(find.byType(CaptureChoiceSheet), findsNothing);

      pickCompleter.complete(XFile(fixturePath));

      String? storedPath;
      for (var i = 0; i < 60; i++) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        await tester.pump(const Duration(milliseconds: 50));
        storedPath = await _readBackgroundLocalPath(db, tripId);
        final completed = events.where(
          (e) => e['event'] == VamoEvent.captureActionCompleted,
        );
        if (storedPath != null && completed.isNotEmpty) break;
      }

      expect(storedPath, isNotNull);
      expect(File(storedPath!).existsSync(), isTrue);

      await tester.pump(const Duration(milliseconds: 100));

      final backdrop = tester.widget<TripVisualBackdrop>(
        find.byType(TripVisualBackdrop),
      );
      expect(backdrop.backgroundImagePath, storedPath);
      expect(find.byType(Image), findsOneWidget);

      expect(
        events.where((e) => e['event'] == VamoEvent.captureActionStarted).single['properties'],
        {
          'screen': 'trip_home',
          'action': 'set_trip_background',
          'sheet_mounted': false,
        },
      );
      expect(
        events.where((e) => e['event'] == VamoEvent.captureActionAbandoned).single['properties'],
        {
          'screen': 'trip_home',
          'action': 'set_trip_background',
          'reason': 'unmounted_after_pick',
        },
      );
      expect(
        events.where((e) => e['event'] == VamoEvent.captureActionCompleted).single['properties'],
        {
          'screen': 'trip_home',
          'action': 'set_trip_background',
        },
      );
      expect(
        events.where((e) => e['event'] == VamoEvent.captureActionAbandoned).length,
        1,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 600));
    },
  );

  testWidgets('tripHeroBackgroundProvider shows the Drift local path', (
    tester,
  ) async {
    await tester.runAsync(
      () => repo
          .setTripBackground(tripId: tripId, sourcePath: fixturePath)
          .timeout(const Duration(seconds: 2)),
    );
    final storedPath = await _readBackgroundLocalPath(db, tripId);
    expect(storedPath, isNotNull);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          supabaseClientProvider.overrideWithValue(client),
          analyticsProvider.overrideWithValue(DebugAnalytics()),
          authRepositoryProvider.overrideWith(
            (ref) => _StubAuthRepository(
              User(
                id: ownerId,
                appMetadata: const {},
                userMetadata: const {},
                aud: 'authenticated',
                createdAt: DateTime.utc(2026, 1, 1).toIso8601String(),
              ),
            ),
          ),
          tripsRepositoryProvider.overrideWith((ref) => repo),
          tripsSyncProvider.overrideWith((ref) async {}),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(body: _HeroProbe(tripId: tripId)),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final backdrop = tester.widget<TripVisualBackdrop>(
      find.byType(TripVisualBackdrop),
    );
    expect(backdrop.backgroundImagePath, storedPath);
    expect(find.byType(Image), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 600));
  });
}

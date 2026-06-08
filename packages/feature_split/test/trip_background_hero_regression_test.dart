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
  });

  final String tripId;
  final String fixturePath;
  final VoidCallback onDismissed;

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

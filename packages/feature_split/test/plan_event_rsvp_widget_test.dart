import 'package:app_core/app_core.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:feature_split/src/plan/event_rsvp_models.dart';
import 'package:feature_split/src/plan/plan_labels.dart';
import 'package:feature_split/src/plan/plan_repository.dart';
import 'package:feature_split/src/plan/plan_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final _planTabLabels = PlanTabLabels(
  tabTitle: 'Plan',
  emptyTitle: 'Nothing on the board yet',
  emptySubtitle: 'Add items for the group.',
  undatedSection: 'No date',
  checklistsSection: 'Checklists',
  addPlanItem: 'Add to plan',
  addListItemHint: 'New checklist item',
  defaultListName: 'Packing',
  deleteItem: 'Delete',
  editItem: 'Edit',
  kindLodging: 'Lodging',
  kindFlight: 'Flight',
  kindTrain: 'Train',
  kindActivity: 'Activity',
  kindOther: 'Other',
  sheetTitleAdd: 'Add plan item',
  sheetTitleEdit: 'Edit plan item',
  fieldTitle: 'Title',
  fieldNotes: 'Notes',
  fieldStart: 'Starts',
  fieldEnd: 'Ends',
  save: 'Save',
  loadError: 'Could not load the plan.',
  checklistsLoadError: 'Could not load checklists.',
  rsvpGoing: 'Going',
  rsvpMaybe: 'Maybe',
  rsvpDeclined: 'Declined',
  rsvpSummary: (going, maybe) => '$going going · $maybe maybe',
);

void main() {
  testWidgets('closed trip hides RSVP controls', (tester) async {
    final db = await _seedEventPlan();
    await _pumpPlanTab(tester, db: db, readOnly: true);
    expect(find.text(_planTabLabels.rsvpGoing), findsNothing);
    expect(find.text(_planTabLabels.rsvpMaybe), findsNothing);
    expect(find.text(_planTabLabels.rsvpDeclined), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    await db.close();
  });

  testWidgets('lodging plan item shows no RSVP controls', (tester) async {
    final db = await _seedEventPlan(includeLodging: true);
    await _pumpPlanTab(tester, db: db, readOnly: false);
    expect(find.text('Beach day'), findsOneWidget);
    expect(find.text('Hotel stay'), findsOneWidget);
    expect(find.text(_planTabLabels.rsvpGoing), findsNWidgets(1));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    await db.close();
  });

  testWidgets('RSVP summary renders from aggregated counts', (tester) async {
    final db = await _seedEventPlan(withCounts: true);
    await _pumpPlanTab(tester, db: db, readOnly: false);
    expect(find.text('3 going · 1 maybe'), findsOneWidget);
    expect(find.textContaining('4 going'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    await db.close();
  });

  testWidgets('tapping selected RSVP chip withdraws via clearEventRsvp', (tester) async {
    final db = await _seedEventPlan(myStatus: EventRsvpStatus.going);
    final client = SupabaseClient(
      'http://localhost',
      'anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    final queue = SyncQueue(db);
    final spy = _SpyPlanRepository(
      db: db,
      client: client,
      analytics: DebugAnalytics(),
      syncQueue: queue,
      syncWorker: SyncWorker(
        queue: queue,
        client: client,
        analytics: DebugAnalytics(),
        flushWithoutSession: true,
        testExecute: (_) async {},
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          analyticsProvider.overrideWithValue(DebugAnalytics()),
          appDatabaseProvider.overrideWithValue(db),
          supabaseClientProvider.overrideWithValue(client),
          planRepositoryProvider.overrideWith((ref) => spy),
          authRepositoryProvider.overrideWith(
            (ref) => _StubAuthRepository(
              User(
                id: 'user-1',
                appMetadata: const {},
                userMetadata: const {},
                aud: 'authenticated',
                createdAt: DateTime.utc(2026, 1, 1).toIso8601String(),
              ),
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: PlanTab(
              tripId: 'trip-1',
              labels: _planTabLabels,
              readOnly: false,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ChoiceChip, 'Going'));
    await tester.pumpAndSettle();

    expect(spy.clearCalls, 1);
    expect(spy.setCalls, 0);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    await db.close();
  });
}

Future<AppDatabase> _seedEventPlan({
  bool includeLodging = false,
  bool withCounts = false,
  EventRsvpStatus? myStatus,
}) async {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  final now = DateTime.utc(2026, 6, 10);

  await db.upsertTrip(
    LocalTripsCompanion(
      id: const Value('trip-1'),
      name: const Value('Test trip'),
      ownerId: const Value('owner'),
      baseCurrency: const Value('EUR'),
      createdAt: Value(now),
      updatedAt: Value(now),
    ),
  );

  await db.upsertPlanItem(
    LocalPlanItemsCompanion(
      id: const Value('event-1'),
      tripId: const Value('trip-1'),
      kind: const Value('activity'),
      title: const Value('Beach day'),
      position: const Value(0),
      createdBy: const Value('owner'),
      createdAt: Value(now),
      updatedAt: Value(now),
    ),
  );

  if (includeLodging) {
    await db.upsertPlanItem(
      LocalPlanItemsCompanion(
        id: const Value('lodging-1'),
        tripId: const Value('trip-1'),
        kind: const Value('lodging'),
        title: const Value('Hotel stay'),
        position: const Value(1),
        createdBy: const Value('owner'),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );
  }

  if (withCounts) {
    final respondedAt = DateTime.utc(2026, 6, 9);
    for (var i = 0; i < 3; i++) {
      await db.upsertPlanItemRsvp(
        LocalPlanItemRsvpsCompanion(
          id: Value('rsvp-going-$i'),
          planItemId: const Value('event-1'),
          userId: Value('user-$i'),
          status: const Value('going'),
          respondedAt: Value(respondedAt),
        ),
      );
    }
    await db.upsertPlanItemRsvp(
      LocalPlanItemRsvpsCompanion(
        id: const Value('rsvp-maybe'),
        planItemId: const Value('event-1'),
        userId: const Value('user-maybe'),
        status: const Value('maybe'),
        respondedAt: Value(respondedAt),
      ),
    );
  }

  if (myStatus != null) {
    await db.upsertPlanItemRsvp(
      LocalPlanItemRsvpsCompanion(
        id: const Value('rsvp-me'),
        planItemId: const Value('event-1'),
        userId: const Value('user-1'),
        status: Value(myStatus.name),
        respondedAt: Value(now),
      ),
    );
  }

  return db;
}

class _StubAuthRepository extends AuthRepository {
  _StubAuthRepository(this._user)
      : super(
          SupabaseClient(
            'http://localhost',
            'anon-key',
            authOptions: const AuthClientOptions(autoRefreshToken: false),
          ),
        );

  final User? _user;

  @override
  User? get currentUser => _user;

  @override
  bool get isSignedIn => _user != null;

  @override
  Stream<AuthState> get authStateChanges => const Stream.empty();
}

Future<void> _pumpPlanTab(
  WidgetTester tester, {
  required AppDatabase db,
  required bool readOnly,
}) async {
  final client = SupabaseClient(
    'http://localhost',
    'anon-key',
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );
  final queue = SyncQueue(db);
  final repo = PlanRepository(
    db: db,
    client: client,
    analytics: DebugAnalytics(),
    syncQueue: queue,
    syncWorker: SyncWorker(
      queue: queue,
      client: client,
      analytics: DebugAnalytics(),
      flushWithoutSession: true,
      testExecute: (_) async {},
    ),
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        analyticsProvider.overrideWithValue(DebugAnalytics()),
        appDatabaseProvider.overrideWithValue(db),
        supabaseClientProvider.overrideWithValue(client),
        planRepositoryProvider.overrideWith((ref) => repo),
        authRepositoryProvider.overrideWith(
          (ref) => _StubAuthRepository(
            User(
              id: 'user-1',
              appMetadata: const {},
              userMetadata: const {},
              aud: 'authenticated',
              createdAt: DateTime.utc(2026, 1, 1).toIso8601String(),
            ),
          ),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: PlanTab(
            tripId: 'trip-1',
            labels: _planTabLabels,
            readOnly: readOnly,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _SpyPlanRepository extends PlanRepository {
  _SpyPlanRepository({
    required super.db,
    required super.client,
    required super.analytics,
    required super.syncQueue,
    required super.syncWorker,
  });

  int clearCalls = 0;
  int setCalls = 0;

  @override
  Future<void> clearEventRsvp({required String planItemId}) async {
    clearCalls++;
  }

  @override
  Future<void> setEventRsvp({
    required String planItemId,
    required EventRsvpStatus status,
  }) async {
    setCalls++;
  }
}

import 'package:app_core/app_core.dart';
import 'package:drift/native.dart';
import 'package:feature_split/src/capture/capture_repository.dart';
import 'package:feature_split/src/expenses/expense_governance.dart';
import 'package:feature_split/src/expenses/expense_models.dart';
import 'package:feature_split/src/expenses/expenses_providers.dart';
import 'package:feature_split/src/expenses/expenses_repository.dart';
import 'package:feature_split/src/plan/plan_repository.dart';
import 'package:feature_split/src/places/places_repository.dart';
import 'package:feature_split/src/settle/settlements_repository.dart';
import 'package:feature_split/src/trips/compact_trip_card.dart';
import 'package:feature_split/src/trips/dashboard_activity_row.dart';
import 'package:feature_split/src/trips/featured_trip_card.dart';
import 'package:feature_split/src/trips/trip_dashboard_tab.dart';
import 'package:feature_split/src/trips/trip_lifecycle_labels.dart';
import 'package:feature_split/src/trips/trips_models.dart';
import 'package:feature_split/src/trips/trips_providers.dart';
import 'package:feature_split/src/trips/trips_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'trip_home_labels_test_support.dart';

class _PreviewAuthRepository extends AuthRepository {
  _PreviewAuthRepository(SupabaseClient client) : super(client);

  @override
  User? get currentUser => User(
        id: 'owner-1',
        appMetadata: const {},
        userMetadata: const {},
        aud: 'authenticated',
        createdAt: DateTime.utc(2026, 1, 1).toIso8601String(),
      );

  @override
  bool get isSignedIn => true;

  @override
  Stream<AuthState> get authStateChanges => const Stream.empty();
}

TripsRepository buildPreviewTripsRepository(AppDatabase db) {
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
  );
}

final s35SampleTrip = TripSummary(
  id: 'trip-amalfi',
  name: 'Amalfi Coast',
  destination: 'Italy',
  startDate: '2026-07-10',
  endDate: '2026-07-17',
  baseCurrency: 'EUR',
);

final s35SecondTrip = TripSummary(
  id: 'trip-rome',
  name: 'Rome weekend',
  destination: 'Italy',
  startDate: '2026-08-01',
  endDate: '2026-08-04',
  baseCurrency: 'EUR',
);

final s35TripDetail = TripDetail(
  id: 'trip-amalfi',
  name: 'Amalfi Coast',
  destination: 'Italy',
  startDate: '2026-07-10',
  endDate: '2026-07-17',
  baseCurrency: 'EUR',
  ownerId: 'owner-1',
);

Widget pumpFeaturedTripCard({
  required ThemeData theme,
  int memberCount = 4,
}) {
  return ProviderScope(
    overrides: [
      tripsSyncProvider.overrideWith((ref) async {}),
      tripsListProvider.overrideWith((ref) => Stream.value([s35SampleTrip])),
      tripCardBackgroundImageProvider(s35SampleTrip.id).overrideWith((ref) => null),
      tripMembersForExpenseProvider(s35SampleTrip.id).overrideWith(
        (ref) => Stream.value(
          List.generate(
            memberCount,
            (i) => TripMemberView(
              userId: 'member-$i',
              displayName: 'Member $i',
              role: i == 0 ? 'owner' : 'member',
            ),
          ),
        ),
      ),
    ],
    child: MaterialApp(
      theme: theme,
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: FeaturedTripCard(
            trip: s35SampleTrip,
            participantsLabel: (c) => '$c Vamigos',
          ),
        ),
      ),
    ),
  );
}

Widget pumpCompactTripCard({
  required ThemeData theme,
  TripSummary? trip,
}) {
  final resolved = trip ?? s35SecondTrip;
  return ProviderScope(
    overrides: [
      tripsSyncProvider.overrideWith((ref) async {}),
      tripsListProvider.overrideWith((ref) => Stream.value([resolved])),
      tripCardBackgroundImageProvider(resolved.id).overrideWith((ref) => null),
      tripMembersForExpenseProvider(resolved.id).overrideWith(
        (ref) => Stream.value([
          const TripMemberView(
            userId: 'owner-1',
            displayName: 'Owner',
            role: 'owner',
          ),
          const TripMemberView(
            userId: 'member-2',
            displayName: 'Member',
            role: 'member',
          ),
          const TripMemberView(
            userId: 'member-3',
            displayName: 'Guest',
            role: 'member',
          ),
        ]),
      ),
    ],
    child: MaterialApp(
      theme: theme,
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: CompactTripCard(
            trip: resolved,
            participantsLabel: (c) => '$c Vamigos',
          ),
        ),
      ),
    ),
  );
}

Widget pumpDashboardActivityRow({required ThemeData theme}) {
  return MaterialApp(
    theme: theme,
    home: Scaffold(
      body: DashboardActivityRow(
        description: 'Dinner at Lo Smeraldo',
        category: 'food',
        amount: '€84.50',
        occurredAt: DateTime(2026, 6, 7, 19, 30),
        now: DateTime(2026, 6, 7, 21),
      ),
    ),
  );
}

const dashboardLifecycleLabels = TripLifecycleLabels(
  markDone: "I'm done",
  requestClose: 'Request close',
  cancelTrip: 'Cancel trip',
  acceptClose: 'Accept close',
  objectToClose: 'Object…',
  withdrawObjection: 'Withdraw objection',
  closeAnyway: 'Close anyway',
  cancelledBanner: 'Trip cancelled — no further activity.',
  closedBanner: 'Trip closed — settling still open.',
  closingBannerGeneric: 'Trip is closing — review balances and respond.',
  closingBannerDays: _dashboardClosingDays,
  objectionNotice:
      'A member objected to closing — discuss or owner may close anyway.',
  markDoneTitle: 'Mark yourself done?',
  markDoneBody: 'Body',
  markDoneConfirm: "I'm done",
  notYet: 'Not yet',
  cancelTripTitle: 'Cancel this trip?',
  cancelTripBody: 'Body',
  keepTrip: 'Keep',
  requestCloseTitle: 'Request trip close?',
  requestCloseBody: 'Members get 14 days to review balances.',
  requestCloseConfirm: 'Request close',
  tripActions: 'Trip actions',
  closeAnywayTitle: 'Close anyway?',
  closeAnywayBody: 'Body',
  closeAnywayHint: 'Type CLOSE to confirm',
  closeAnywayPhrase: 'CLOSE',
  closeTrip: 'Close trip',
  back: 'Back',
  objectTitle: 'Object to closing',
  objectReasonLabel: 'Reason (required)',
  objectReasonHint: 'Hint',
  submitObjection: 'Submit objection',
);

String _dashboardClosingDays(int days) => 'Closing in $days days';

final dashboardPreviewMembers = [
  const TripMemberView(userId: '1', displayName: 'Alex', role: 'owner'),
  const TripMemberView(userId: '2', displayName: 'Sam', role: 'member'),
  const TripMemberView(userId: '3', displayName: 'Jordan', role: 'member'),
];

final dashboardPreviewExpenses = [
  ExpenseSummary(
    id: 'e1',
    tripId: s35TripDetail.id,
    description: 'Dinner at Lo Smeraldo',
    amountCents: 8450,
    baseCents: 8450,
    currency: 'EUR',
    payerId: '1',
    spentAt: DateTime(2026, 6, 7, 19, 30),
    status: ExpenseStatus.committed,
    category: 'food',
  ),
  ExpenseSummary(
    id: 'e2',
    tripId: s35TripDetail.id,
    description: 'Ferry tickets',
    amountCents: 4200,
    baseCents: 4200,
    currency: 'EUR',
    payerId: '2',
    spentAt: DateTime(2026, 6, 6, 10, 15),
    status: ExpenseStatus.committed,
    category: 'transport',
  ),
];

Widget pumpTripDashboardTab({
  required ThemeData theme,
  TripDetail? detail,
  String? heroBackgroundPath,
}) {
  final trip = detail ?? s35TripDetail;
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  final client = SupabaseClient(
    'http://localhost',
    'anon-key',
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );
  return ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      analyticsProvider.overrideWithValue(DebugAnalytics()),
      supabaseClientProvider.overrideWithValue(client),
      authRepositoryProvider.overrideWith((ref) => _PreviewAuthRepository(client)),
      tripsRepositoryProvider.overrideWith((ref) => buildPreviewTripsRepository(db)),
      tripDetailProvider(trip.id).overrideWith((ref) => Stream.value(trip)),
      tripHeroBackgroundProvider(trip.id)
          .overrideWith((ref) => Future.value(heroBackgroundPath)),
      tripMyMemberProvider(trip.id).overrideWith((ref) => Stream.value(null)),
      tripHasCloseObjectionProvider(trip.id)
          .overrideWith((ref) => Stream.value(false)),
      tripMembersForExpenseProvider(trip.id)
          .overrideWith((ref) => Stream.value(dashboardPreviewMembers)),
      tripExpensesProvider(trip.id)
          .overrideWith((ref) => Stream.value(dashboardPreviewExpenses)),
    ],
    child: MaterialApp(
      theme: theme,
      home: MediaQuery(
        data: const MediaQueryData(padding: EdgeInsets.only(top: 24)),
        child: Scaffold(
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            foregroundColor: Colors.white,
            iconTheme: const IconThemeData(color: Colors.white),
            actionsIconTheme: const IconThemeData(color: Colors.white),
            leading: const Icon(Icons.arrow_back, color: Colors.white),
            actions: const [
              Icon(Icons.more_horiz, color: Colors.white),
            ],
          ),
          body: TripDashboardTab(
            tripId: trip.id,
            detail: trip,
            labels: testTripHomeLabels,
            lifecycleLabels: dashboardLifecycleLabels,
            readOnly: false,
            showBalances: true,
            onExpenses: () {},
            onPlans: () {},
            onBalances: () {},
            onMembers: () {},
            onMemories: () {},
            onInvite: () {},
          ),
        ),
      ),
    ),
  );
}

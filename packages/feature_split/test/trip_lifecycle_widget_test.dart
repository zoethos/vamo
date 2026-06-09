import 'package:app_core/app_core.dart';
import 'package:drift/native.dart';
import 'package:feature_split/src/expenses/expense_consent_providers.dart';
import 'package:feature_split/src/expenses/expense_governance_labels.dart';
import 'package:feature_split/src/expenses/expenses_providers.dart';
import 'package:feature_split/src/expenses/expense_models.dart';


import 'trip_home_labels_test_support.dart';
import 'trips_repository_test_support.dart';
import 'package:feature_split/src/plan/plan_providers.dart';
import 'package:feature_split/src/sync/trip_realtime_binding.dart';
import 'package:feature_split/src/trips/trip_budget_labels.dart';
import 'package:feature_split/src/capture/capture_repository.dart';
import 'package:feature_split/src/expenses/expenses_repository.dart';
import 'package:feature_split/src/plan/plan_repository.dart';
import 'package:feature_split/src/places/places_repository.dart';
import 'package:feature_split/src/settle/settlements_repository.dart';
import 'package:feature_split/src/trips/trip_expenses_screen.dart';
import 'package:feature_split/src/trips/trip_home_screen.dart';
import 'package:feature_split/src/trips/trip_lifecycle_labels.dart';
import 'package:feature_split/src/trips/trips_models.dart';
import 'package:feature_split/src/trips/trips_providers.dart';
import 'package:feature_split/src/trips/trips_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

class _SpyTripsRepository extends TripsRepository {
  _SpyTripsRepository({
    required super.db,
    required super.client,
    required super.analytics,
    required super.expenses,
    required super.settlements,
    required super.capture,
    required super.places,
    required super.plan,
    required super.syncQueue,
  });

  int requestCloseCalls = 0;

  @override
  Future<void> requestTripClose(String tripId) async {
    requestCloseCalls++;
  }
}

_SpyTripsRepository _buildSpyTripsRepository(AppDatabase db) {
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
  final expenses = ExpensesRepository(
    db: db,
    client: client,
    analytics: analytics,
    fxRates: fxRates,
    syncQueue: queue,
    syncWorker: syncWorker,
  );
  final settlements = SettlementsRepository(
    db: db,
    client: client,
    analytics: analytics,
    syncQueue: queue,
    syncWorker: syncWorker,
  );
  final capture = CaptureRepository(
    db: db,
    client: client,
    syncQueue: queue,
    syncWorker: syncWorker,
  );
  final places = PlacesRepository(
    db: db,
    client: client,
    analytics: analytics,
    syncQueue: queue,
  );
  final plan = PlanRepository(
    db: db,
    client: client,
    analytics: analytics,
    syncQueue: queue,
    syncWorker: syncWorker,
  );
  return _SpyTripsRepository(
    db: db,
    client: client,
    analytics: analytics,
    expenses: expenses,
    settlements: settlements,
    capture: capture,
    places: places,
    plan: plan,
    syncQueue: queue,
  );
}

const _lifecycleLabels = TripLifecycleLabels(
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
  closingBannerDays: _mockClosingDays,
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

String _mockClosingDays(int days) =>
    'Trip closes in $days days unless someone objects.';

const _governanceLabels = ExpenseGovernanceLabels(
  includedDisputedBy: _mockDisputedBy,
  includedPendingFrom: _mockPendingFrom,
  someoneFallback: 'Someone',
  proposalRowPrefix: 'Proposal',
  proposalNotInBalances: 'Not in balances',
  shareAccepted: 'Accepted',
  yourShare: 'Your share',
  dispute: 'Dispute',
  accept: 'Accept',
  commitToBalances: 'Commit',
  voidProposal: 'Void',
  disputeReasonTitle: 'Reason',
  disputeReasonHint: 'Hint',
  cancel: 'Cancel',
  submit: 'Submit',
  proposeCostAction: 'Propose',
  addExpenseTitle: 'Add expense',
  proposeCostTitle: 'Propose cost',
  saveExpense: 'Save',
  saveProposal: 'Save proposal',
  tripBalancesIn: _mockBalancesIn,
  splitEqual: _mockSplitEqual,
  splitSolo: 'All on you (solo)',
);

String _mockDisputedBy(String name) => 'Disputed by $name';
String _mockPendingFrom(String name) => 'Pending from $name';
String _mockBalancesIn(String currency) => 'Balances in $currency';
String _mockSplitEqual(int count) => 'Split equally · $count Vamigos';

const _budgetLabels = TripBudgetLabels(
  settingsTitle: 'Trip settings',
  budgetSectionTitle: 'Budget',
  budgetModeNone: 'No budget',
  budgetModeInformational: 'Informational',
  budgetModeFormal: 'Formal',
  budgetAmountLabel: 'Amount',
  saveBudget: 'Save budget',
  burnDownRemaining: _mockRemaining,
  burnDownOver: _mockOver,
  fxSectionTitle: 'Exchange rates',
  fxAddCurrency: 'Add currency',
  fxRefresh: 'Refresh',
  fxCapturedAt: _mockCapturedAt,
  fxSource: 'Source',
  fxRateReadOnly: 'Market rates only — not editable',
  overBudgetCommitTitle: 'Over budget',
  overBudgetCommitBody: 'Confirm to proceed',
  overBudgetConfirmHint: _mockHint,
  overBudgetConfirmPhrase: 'OVER BUDGET',
  confirm: 'Confirm',
  cancel: 'Cancel',
  currencyMissingAdmin: 'Ask admin',
);

String _mockRemaining(int cents, String currency) => '$cents $currency left';
String _mockOver(String currency) => 'Over $currency';
String _mockCapturedAt(String iso) => 'Captured $iso';
String _mockHint(String phrase) => 'Type $phrase';

Future<void> _openOverflowMenu(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.more_horiz));
  await tester.pumpAndSettle();
}

List<Override> _tripHomeOverrides({
  required String tripId,
  required TripDetail detail,
  required String currentUserId,
  required String memberRole,
  LocalTripMember? myMember,
  bool hasCloseObjection = false,
  required AppDatabase db,
  TripsRepository? tripsRepo,
}) {
  final client = SupabaseClient(
    'http://localhost',
    'anon-key',
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );

  return [
    appDatabaseProvider.overrideWithValue(db),
    supabaseClientProvider.overrideWithValue(client),
    analyticsProvider.overrideWithValue(DebugAnalytics()),
    authRepositoryProvider.overrideWith(
      (ref) => _StubAuthRepository(
        User(
          id: currentUserId,
          appMetadata: const {},
          userMetadata: const {},
          aud: 'authenticated',
          createdAt: DateTime.utc(2026, 1, 1).toIso8601String(),
        ),
      ),
    ),
    tripRealtimeBindingProvider(tripId).overrideWith((ref) {}),
    tripsSyncProvider.overrideWith((ref) async {}),
    tripHeroBackgroundProvider(tripId).overrideWith((ref) => null),
    tripDetailProvider(tripId).overrideWith((ref) => Stream.value(detail)),
    tripMemberCountProvider(tripId).overrideWith((ref) => Stream.value(1)),
    tripMyMemberProvider(tripId).overrideWith((ref) => Stream.value(myMember)),
    tripHasCloseObjectionProvider(tripId)
        .overrideWith((ref) => Stream.value(hasCloseObjection)),
    tripExpensesProvider(tripId).overrideWith((ref) => Stream.value([])),
    tripExpenseSharesProvider(tripId).overrideWith((ref) => Stream.value([])),
    tripMembersForExpenseProvider(tripId).overrideWith(
      (ref) => Stream.value([
        TripMemberView(
          userId: detail.ownerId,
          displayName: 'Owner',
          role: 'owner',
        ),
        TripMemberView(
          userId: currentUserId == detail.ownerId ? 'member-1' : currentUserId,
          displayName: 'Member',
          role: currentUserId == detail.ownerId ? 'member' : memberRole,
        ),
      ]),
    ),
    tripPlanItemsProvider(tripId).overrideWith((ref) => Stream.value([])),
    tripListItemsProvider(tripId).overrideWith((ref) => Stream.value([])),
    tripFxRatesProvider(tripId).overrideWith((ref) => Stream.value([])),
    currentUserProvider.overrideWith(
      (ref) => User(
        id: currentUserId,
        appMetadata: const {},
        userMetadata: const {},
        aud: 'authenticated',
        createdAt: DateTime.utc(2026, 1, 1).toIso8601String(),
      ),
    ),
    currentMemberRoleProvider.overrideWith(
      (ref, args) => memberRole,
    ),
    if (tripsRepo != null)
      tripsRepositoryProvider.overrideWith((ref) => tripsRepo)
    else
      tripsRepositoryProvider.overrideWith((ref) => buildTestTripsRepository(db)),
  ];
}

Widget _tripHome({
  required String tripId,
  required List<Override> overrides,
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: AppTheme.light,
      home: TripHomeScreen(
        tripId: tripId,
        lifecycleLabels: _lifecycleLabels,
        tripHomeLabels: testTripHomeLabels,
      ),
    ),
  );
}

Widget _tripHomeRouter({
  required String tripId,
  required List<Override> overrides,
}) {
  final router = GoRouter(
    initialLocation: '/trips/$tripId',
    routes: [
      GoRoute(
        path: AppRoutes.trips,
        builder: (context, state) => const Scaffold(
          body: Center(child: Text('Trips list')),
        ),
      ),
      GoRoute(
        path: '/trips/:tripId',
        builder: (context, state) => TripHomeScreen(
          tripId: state.pathParameters['tripId']!,
          lifecycleLabels: _lifecycleLabels,
          tripHomeLabels: testTripHomeLabels,
        ),
      ),
    ],
  );

  return ProviderScope(
    overrides: overrides,
    child: MaterialApp.router(
      theme: AppTheme.light,
      routerConfig: router,
    ),
  );
}

Future<void> _flushPendingTimers(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  const tripId = 'trip-lifecycle-ui';

  testWidgets('trip header back falls back to trips list when no pop stack',
      (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      _tripHomeRouter(
        tripId: tripId,
        overrides: _tripHomeOverrides(
          tripId: tripId,
          db: db,
          currentUserId: 'owner',
          memberRole: 'owner',
          detail: const TripDetail(
            id: tripId,
            name: 'Direct trip',
            baseCurrency: 'EUR',
            ownerId: 'owner',
            lifecycle: 'active',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Direct trip'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    expect(find.text('Trips list'), findsOneWidget);
    await _flushPendingTimers(tester);
  });

  testWidgets(
      'pre-start owner overflow has cancel only; no done or request close in body',
      (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final futureStart = DateTime.now().add(const Duration(days: 14));
    final startDate =
        '${futureStart.year.toString().padLeft(4, '0')}-${futureStart.month.toString().padLeft(2, '0')}-${futureStart.day.toString().padLeft(2, '0')}';

    await tester.pumpWidget(
      _tripHome(
        tripId: tripId,
        overrides: _tripHomeOverrides(
          tripId: tripId,
          db: db,
          currentUserId: 'owner',
          memberRole: 'owner',
          detail: TripDetail(
            id: tripId,
            name: 'Future trip',
            baseCurrency: 'EUR',
            ownerId: 'owner',
            startDate: startDate,
            lifecycle: 'active',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text("I'm done"), findsNothing);
    expect(find.text('Request close'), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);

    await _openOverflowMenu(tester);
    expect(find.text('Cancel trip'), findsOneWidget);
    expect(find.text('Request close'), findsNothing);
    expect(find.text("I'm done"), findsNothing);
    await _flushPendingTimers(tester);
  });

  testWidgets(
      'ongoing owner overflow has request close and done; cancel absent',
      (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final pastStart = DateTime.now().subtract(const Duration(days: 3));
    final startDate =
        '${pastStart.year.toString().padLeft(4, '0')}-${pastStart.month.toString().padLeft(2, '0')}-${pastStart.day.toString().padLeft(2, '0')}';

    await tester.pumpWidget(
      _tripHome(
        tripId: tripId,
        overrides: _tripHomeOverrides(
          tripId: tripId,
          db: db,
          currentUserId: 'owner',
          memberRole: 'owner',
          detail: TripDetail(
            id: tripId,
            name: 'Active trip',
            baseCurrency: 'EUR',
            ownerId: 'owner',
            startDate: startDate,
            lifecycle: 'active',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text("I'm done"), findsNothing);
    expect(find.text('Request close'), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);

    await _openOverflowMenu(tester);
    expect(find.text('Request close'), findsOneWidget);
    expect(find.text("I'm done"), findsOneWidget);
    expect(find.text('Cancel trip'), findsNothing);
    await _flushPendingTimers(tester);
  });

  testWidgets('request close shows confirm dialog before RPC', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final spy = _buildSpyTripsRepository(db);
    final pastStart = DateTime.now().subtract(const Duration(days: 3));
    final startDate =
        '${pastStart.year.toString().padLeft(4, '0')}-${pastStart.month.toString().padLeft(2, '0')}-${pastStart.day.toString().padLeft(2, '0')}';

    await tester.pumpWidget(
      _tripHome(
        tripId: tripId,
        overrides: _tripHomeOverrides(
          tripId: tripId,
          db: db,
          tripsRepo: spy,
          currentUserId: 'owner',
          memberRole: 'owner',
          detail: TripDetail(
            id: tripId,
            name: 'Active trip',
            baseCurrency: 'EUR',
            ownerId: 'owner',
            startDate: startDate,
            lifecycle: 'active',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _openOverflowMenu(tester);
    await tester.tap(find.text('Request close').last);
    await tester.pumpAndSettle();

    expect(find.text(_lifecycleLabels.requestCloseTitle), findsOneWidget);
    expect(spy.requestCloseCalls, 0);

    await tester.tap(find.text(_lifecycleLabels.notYet));
    await tester.pumpAndSettle();
    expect(spy.requestCloseCalls, 0);

    await _openOverflowMenu(tester);
    await tester.tap(find.text('Request close').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(_lifecycleLabels.requestCloseConfirm));
    await tester.pumpAndSettle();

    expect(spy.requestCloseCalls, 1);
    await _flushPendingTimers(tester);
  });

  testWidgets('ongoing member sees done only in overflow', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.pumpWidget(
      _tripHome(
        tripId: tripId,
        overrides: _tripHomeOverrides(
          tripId: tripId,
          db: db,
          currentUserId: 'member-1',
          memberRole: 'member',
          detail: const TripDetail(
            id: tripId,
            name: 'Active trip',
            baseCurrency: 'EUR',
            ownerId: 'owner',
            lifecycle: 'active',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _openOverflowMenu(tester);
    expect(find.text("I'm done"), findsOneWidget);
    expect(find.text('Request close'), findsNothing);
    expect(find.text('Cancel trip'), findsNothing);
    await _flushPendingTimers(tester);
  });

  testWidgets('closing banner keeps accept and object actions', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.pumpWidget(
      _tripHome(
        tripId: tripId,
        overrides: _tripHomeOverrides(
          tripId: tripId,
          db: db,
          currentUserId: 'owner',
          memberRole: 'owner',
          detail: TripDetail(
            id: tripId,
            name: 'Closing trip',
            baseCurrency: 'EUR',
            ownerId: 'owner',
            lifecycle: 'closing',
            closeRequestedAt: DateTime.utc(2026, 6, 1),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Accept close'), findsOneWidget);
    expect(find.text('Object…'), findsOneWidget);
    expect(find.byIcon(Icons.more_vert), findsNothing);
    await _flushPendingTimers(tester);
  });

  testWidgets('trip home renders dashboard without tab strip', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      _tripHome(
        tripId: tripId,
        overrides: _tripHomeOverrides(
          tripId: tripId,
          db: db,
          currentUserId: 'owner',
          memberRole: 'owner',
          detail: const TripDetail(
            id: tripId,
            name: 'Dashboard trip',
            baseCurrency: 'EUR',
            ownerId: 'owner',
            lifecycle: 'active',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TabBar), findsNothing);
    expect(find.byType(TabBarView), findsNothing);
    expect(find.text('Dashboard trip'), findsOneWidget);
    expect(find.text(testTripHomeLabels.quickExpenses), findsOneWidget);
    expect(find.text(testTripHomeLabels.quickBalances), findsOneWidget);
    await _flushPendingTimers(tester);
  });

  testWidgets('quick action opens expenses section route', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    final router = GoRouter(
      initialLocation: '/trips/$tripId',
      routes: [
        GoRoute(
          path: '/trips/:tripId',
          routes: [
            GoRoute(
              path: 'expenses',
              builder: (context, state) => TripExpensesScreen(
                tripId: state.pathParameters['tripId']!,
                tripHomeLabels: testTripHomeLabels,
                governanceLabels: _governanceLabels,
                budgetLabels: _budgetLabels,
              ),
            ),
          ],
          builder: (context, state) => TripHomeScreen(
            tripId: state.pathParameters['tripId']!,
            lifecycleLabels: _lifecycleLabels,
            tripHomeLabels: testTripHomeLabels,
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: _tripHomeOverrides(
          tripId: tripId,
          db: db,
          currentUserId: 'owner',
          memberRole: 'owner',
          detail: const TripDetail(
            id: tripId,
            name: 'Nav trip',
            baseCurrency: 'EUR',
            ownerId: 'owner',
            lifecycle: 'active',
          ),
        ),
        child: MaterialApp.router(
          theme: AppTheme.light,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(testTripHomeLabels.quickExpenses));
    await tester.pumpAndSettle();

    expect(find.text(testTripHomeLabels.tabExpenses), findsOneWidget);
    await _flushPendingTimers(tester);
  });
}

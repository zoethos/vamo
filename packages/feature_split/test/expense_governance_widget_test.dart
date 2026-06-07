import 'package:app_core/app_core.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:feature_split/src/expenses/add_expense_screen_labels.dart';
import 'package:feature_split/src/expenses/add_expense_screen.dart';
import 'package:feature_split/src/expenses/expense_consent_providers.dart';
import 'package:feature_split/src/expenses/expense_governance.dart';
import 'package:feature_split/src/expenses/expense_governance_labels.dart';
import 'package:feature_split/src/expenses/expense_models.dart';
import 'package:feature_split/src/expenses/expenses_providers.dart';
import 'package:feature_split/src/expenses/expenses_repository.dart';
import 'package:feature_split/src/expenses/trip_expense_list_tile.dart';
import 'package:feature_split/src/expenses/trip_expenses_propose_action.dart';
import 'package:feature_split/src/trips/trips_models.dart';
import 'package:feature_split/src/trips/trips_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'governance_test_labels.dart';

const _addExpenseScreenLabels = AddExpenseScreenLabels(
  title: 'Add expense',
  tripNotFound: 'Trip not found',
  scanReceipt: 'Scan receipt',
  takePhoto: 'Take photo',
  chooseGallery: 'Choose from gallery',
  choosePayer: 'Choose who paid.',
);

class _SpyExpensesRepository extends ExpensesRepository {
  _SpyExpensesRepository({
    required super.db,
    required super.client,
    required super.analytics,
    required super.syncQueue,
    required super.syncWorker,
    required super.fxRates,
  });

  int proposeCalls = 0;
  int addCalls = 0;

  @override
  Future<String> proposeExpense({
    required String tripId,
    required String payerId,
    required String description,
    required int amountCents,
    required String currency,
    required int baseCents,
    required double fxRate,
  }) async {
    proposeCalls++;
    return 'proposed-expense-id';
  }

  @override
  Future<AddExpenseResult> addExpense({
    required AddExpenseInput input,
    required String baseCurrency,
  }) async {
    addCalls++;
    return const AddExpenseResult(expenseId: 'committed-id');
  }
}

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

Future<AppDatabase> _seedActiveTrip({
  required String tripId,
  required List<TripMemberView> members,
}) async {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  final now = DateTime.utc(2026, 6, 5);
  await db.upsertTrip(
    LocalTripsCompanion(
      id: Value(tripId),
      name: const Value('Test trip'),
      baseCurrency: const Value('EUR'),
      ownerId: Value(members.first.userId),
      createdAt: Value(now),
      updatedAt: Value(now),
      lifecycle: const Value('active'),
    ),
  );
  for (final member in members) {
    await db.upsertMember(
      LocalTripMembersCompanion(
        tripId: Value(tripId),
        userId: Value(member.userId),
        displayName: Value(member.displayName),
        role: Value(member.role),
        status: const Value('active'),
      ),
    );
  }
  return db;
}

List<Override> _proposeScreenOverrides({
  required AppDatabase db,
  required _SpyExpensesRepository spy,
  required String tripId,
  required String memberRole,
  required Analytics analytics,
}) {
  final client = SupabaseClient(
    'http://localhost',
    'anon-key',
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );
  return [
    appDatabaseProvider.overrideWithValue(db),
    supabaseClientProvider.overrideWithValue(client),
    analyticsProvider.overrideWithValue(analytics),
    expensesRepositoryProvider.overrideWith((ref) => spy),
    tripDetailProvider(tripId).overrideWith(
      (ref) => Stream.value(
        TripDetail(
          id: tripId,
          name: 'Test trip',
          baseCurrency: 'EUR',
          ownerId: 'owner',
          lifecycle: 'active',
        ),
      ),
    ),
    tripMembersForExpenseProvider(tripId).overrideWith(
      (ref) => Stream.value(const [
        TripMemberView(
          userId: 'owner',
          displayName: 'Owner',
          role: 'owner',
        ),
        TripMemberView(
          userId: 'member-1',
          displayName: 'Member',
          role: 'member',
        ),
      ]),
    ),
    currentMemberRoleProvider.overrideWith(
      (ref, args) => args.userId == 'owner' ? 'owner' : memberRole,
    ),
    currentUserProvider.overrideWith(
      (ref) => User(
        id: memberRole == 'member' ? 'member-1' : 'owner',
        appMetadata: const {},
        userMetadata: const {},
        aud: 'authenticated',
        createdAt: DateTime.utc(2026, 1, 1).toIso8601String(),
      ),
    ),
    tripFxRatesProvider(tripId).overrideWith((ref) => Stream.value([])),
  ];
}

GoRouter _proposeGoRouter({required String tripId}) {
  return GoRouter(
    initialLocation: '/trips/$tripId/expenses/propose',
    routes: [
      GoRoute(
        path: '/trips/:tripId',
        builder: (_, state) => Scaffold(
          body: Text('trip-${state.pathParameters['tripId']}'),
        ),
        routes: [
          GoRoute(
            path: 'expenses/propose',
            builder: (_, state) => AddExpenseScreen(
              tripId: state.pathParameters['tripId']!,
              mode: AddExpenseMode.proposed,
              labels: governanceTestLabels,
              screenLabels: _addExpenseScreenLabels,
            ),
          ),
        ],
      ),
    ],
  );
}

void main() {
  test('Arabic governance labels avoid hardcoded English disputed copy', () {
    final label = governanceTestLabelsAr.consentDisplayLabel(
      memberName: 'أحمد',
      response: ShareResponse.rejected,
    );
    expect(label, governanceTestLabelsAr.includedDisputedBy('أحمد'));
    expect(label, isNot(contains('included — disputed by')));
  });

  testWidgets('TripExpensesProposeAction absent when not visible', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: TripExpensesProposeAction(
            visible: false,
            labels: governanceTestLabels,
            onPressed: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text(governanceTestLabels.proposeCostAction), findsNothing);
    expect(find.byType(TextButton), findsNothing);
  });

  testWidgets('TripExpensesProposeAction present for trip admin', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: TripExpensesProposeAction(
            visible: true,
            labels: governanceTestLabels,
            onPressed: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text(governanceTestLabels.proposeCostAction), findsOneWidget);
  });

  testWidgets('proposed expense tile uses ghost styling', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: TripExpenseListTile(
            description: 'Hotel deposit',
            payer: 'Alex',
            spentAt: DateTime.utc(2026, 7, 1),
            baseCents: 5000,
            amountCents: 5000,
            tripBaseCurrency: 'EUR',
            expenseCurrency: 'EUR',
            status: ExpenseStatus.proposed,
            proposalRowPrefix: governanceTestLabels.proposalRowPrefix,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.textContaining(governanceTestLabels.proposalRowPrefix),
      findsOneWidget,
    );
  });

  testWidgets('disputed label renders from labels bundle', (tester) async {
    const memberName = 'Marco';
    final consentLabel = governanceTestLabels.consentDisplayLabel(
      memberName: memberName,
      response: ShareResponse.rejected,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: TripExpenseListTile(
            description: 'Dinner',
            payer: 'Alex',
            spentAt: DateTime.utc(2026, 7, 1),
            baseCents: 3000,
            amountCents: 3000,
            tripBaseCurrency: 'EUR',
            expenseCurrency: 'EUR',
            consentLabel: consentLabel,
            proposalRowPrefix: governanceTestLabels.proposalRowPrefix,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining(consentLabel), findsOneWidget);
  });

  testWidgets('propose mode hides receipt and place inputs', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    const tripId = 'trip-1';
    final db = await _seedActiveTrip(
      tripId: tripId,
      members: const [
        TripMemberView(userId: 'owner', displayName: 'Owner', role: 'owner'),
      ],
    );
    addTearDown(db.close);

    final queue = SyncQueue(db);
    final client = SupabaseClient(
      'http://localhost',
      'anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    final spy = _SpyExpensesRepository(
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
      fxRates: FxRatesClient(),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: _proposeScreenOverrides(
          db: db,
          spy: spy,
          tripId: tripId,
          memberRole: 'owner',
          analytics: DebugAnalytics(),
        ),
        child: MaterialApp.router(
          theme: AppTheme.light,
          routerConfig: _proposeGoRouter(tripId: tripId),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(governanceTestLabels.saveProposal), findsOneWidget);
    expect(find.text('Scan receipt'), findsNothing);
    expect(find.text('Place'), findsNothing);
  });

  testWidgets('propose route bounces members before showing the form', (
    tester,
  ) async {
    const tripId = 'trip-1';
    final db = await _seedActiveTrip(
      tripId: tripId,
      members: const [
        TripMemberView(userId: 'owner', displayName: 'Owner', role: 'owner'),
        TripMemberView(
          userId: 'member-1',
          displayName: 'Member',
          role: 'member',
        ),
      ],
    );
    addTearDown(db.close);

    final queue = SyncQueue(db);
    final client = SupabaseClient(
      'http://localhost',
      'anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    final spy = _SpyExpensesRepository(
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
      fxRates: FxRatesClient(),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: _proposeScreenOverrides(
          db: db,
          spy: spy,
          tripId: tripId,
          memberRole: 'member',
          analytics: DebugAnalytics(),
        ),
        child: MaterialApp.router(
          theme: AppTheme.light,
          routerConfig: _proposeGoRouter(tripId: tripId),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(governanceTestLabels.saveProposal), findsNothing);
    expect(find.text('Scan receipt'), findsNothing);
    expect(find.text('trip-$tripId'), findsOneWidget);
  });

  testWidgets('propose mode saves via RPC and pops without action_failed', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    const tripId = 'trip-1';
    final db = await _seedActiveTrip(
      tripId: tripId,
      members: const [
        TripMemberView(userId: 'owner', displayName: 'Owner', role: 'owner'),
      ],
    );
    addTearDown(db.close);

    final events = <Map<String, Object?>>[];
    final analytics = _RecordingAnalytics(events);

    final queue = SyncQueue(db);
    final client = SupabaseClient(
      'http://localhost',
      'anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    final spy = _SpyExpensesRepository(
      db: db,
      client: client,
      analytics: analytics,
      syncQueue: queue,
      syncWorker: SyncWorker(
        queue: queue,
        client: client,
        analytics: analytics,
        flushWithoutSession: true,
        testExecute: (_) async {},
      ),
      fxRates: FxRatesClient(),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: _proposeScreenOverrides(
          db: db,
          spy: spy,
          tripId: tripId,
          memberRole: 'owner',
          analytics: analytics,
        ),
        child: MaterialApp.router(
          theme: AppTheme.light,
          routerConfig: _proposeGoRouter(tripId: tripId),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, '50');
    await tester.enterText(find.byType(TextFormField).at(1), 'Hotel deposit');
    await tester.ensureVisible(find.text(governanceTestLabels.saveProposal));
    await tester.tap(find.text(governanceTestLabels.saveProposal));
    await tester.pumpAndSettle();

    expect(spy.proposeCalls, 1);
    expect(spy.addCalls, 0);
    expect(find.text('trip-$tripId'), findsOneWidget);
    expect(
      events.where((e) => e['event'] == VamoEvent.actionFailed),
      isEmpty,
    );
  });
}

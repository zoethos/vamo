import 'package:app_core/app_core.dart';
import 'package:drift/native.dart';
import 'package:feature_split/src/capture/capture_action_sheet.dart';
import 'package:feature_split/src/expenses/expense_consent_providers.dart';
import 'package:feature_split/src/expenses/expense_models.dart';
import 'package:feature_split/src/expenses/expenses_providers.dart';
import 'package:feature_split/src/sync/trip_realtime_binding.dart';
import 'package:feature_split/src/trips/trip_home_screen.dart';
import 'package:feature_split/src/trips/trip_lifecycle_labels.dart';
import 'package:feature_split/src/trips/trips_models.dart';
import 'package:feature_split/src/trips/trips_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'trip_home_labels_test_support.dart';

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
  closingBannerDays: _closingDays,
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

String _closingDays(int days) =>
    'Trip closes in $days days unless someone objects.';

List<Override> _tripHomeOverrides({
  required String tripId,
  required TripDetail detail,
  required AppDatabase db,
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
          id: detail.ownerId,
          appMetadata: const {},
          userMetadata: const {},
          aud: 'authenticated',
          createdAt: DateTime.utc(2026, 1, 1).toIso8601String(),
        ),
      ),
    ),
    tripRealtimeBindingProvider(tripId).overrideWith((ref) {}),
    tripDetailProvider(tripId).overrideWith((ref) => Stream.value(detail)),
    tripHeroBackgroundProvider(tripId)
        .overrideWith((ref) => Future.value(null)),
    tripMemberCountProvider(tripId).overrideWith((ref) => Stream.value(2)),
    tripMyMemberProvider(tripId).overrideWith((ref) => Stream.value(null)),
    tripHasCloseObjectionProvider(tripId)
        .overrideWith((ref) => Stream.value(false)),
    tripExpensesProvider(tripId).overrideWith((ref) => Stream.value([])),
    tripMembersForExpenseProvider(tripId).overrideWith(
      (ref) => Stream.value([
        TripMemberView(
          userId: detail.ownerId,
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
    currentUserProvider.overrideWith(
      (ref) => User(
        id: detail.ownerId,
        appMetadata: const {},
        userMetadata: const {},
        aud: 'authenticated',
        createdAt: DateTime.utc(2026, 1, 1).toIso8601String(),
      ),
    ),
    currentMemberRoleProvider.overrideWith((ref, args) => 'owner'),
  ];
}

class _StubAuthRepository extends AuthRepository {
  _StubAuthRepository(this._user) : super(_noopClient());

  static SupabaseClient _noopClient() => SupabaseClient(
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

void main() {
  const tripId = 'trip-quick-actions';

  testWidgets(
      'dashboard quick actions scroll with five tiles including Memories',
      (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: _tripHomeOverrides(
          tripId: tripId,
          db: db,
          detail: const TripDetail(
            id: tripId,
            name: 'Quick actions trip',
            baseCurrency: 'EUR',
            ownerId: 'owner',
            lifecycle: 'active',
          ),
        ),
        child: MaterialApp(
          theme: AppTheme.light,
          home: TripHomeScreen(
            tripId: tripId,
            lifecycleLabels: _lifecycleLabels,
            tripHomeLabels: testTripHomeLabels,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SingleChildScrollView), findsWidgets);
    expect(find.text(testTripHomeLabels.quickMemories), findsOneWidget);
    expect(find.text(testTripHomeLabels.quickExpenses), findsOneWidget);
    expect(find.text(testTripHomeLabels.quickPlans), findsOneWidget);
    expect(find.text(testTripHomeLabels.quickBalances), findsOneWidget);
    expect(find.text(testTripHomeLabels.quickMembers), findsOneWidget);
  });

  testWidgets('hero camera opens capture choice sheet', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: _tripHomeOverrides(
          tripId: tripId,
          db: db,
          detail: const TripDetail(
            id: tripId,
            name: 'Capture sheet trip',
            baseCurrency: 'EUR',
            ownerId: 'owner',
            lifecycle: 'active',
          ),
        ),
        child: MaterialApp(
          theme: AppTheme.light,
          home: TripHomeScreen(
            tripId: tripId,
            lifecycleLabels: _lifecycleLabels,
            tripHomeLabels: testTripHomeLabels,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip(testTripHomeLabels.tabCapture));
    await tester.pumpAndSettle();

    expect(find.byType(CaptureChoiceSheet), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(ListWheelScrollView), findsOneWidget);
    expect(find.text('Photo'), findsOneWidget);
    expect(find.bySemanticsLabel('Background'), findsOneWidget);
  });

  testWidgets('Memories quick action opens memories route', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    final router = GoRouter(
      initialLocation: '/trips/$tripId',
      routes: [
        GoRoute(
          path: '/trips/:tripId',
          routes: [
            GoRoute(
              path: 'memories',
              builder: (context, state) => Scaffold(
                appBar: AppBar(title: Text(testTripHomeLabels.memoriesTitle)),
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
          detail: const TripDetail(
            id: tripId,
            name: 'Memories nav trip',
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

    await tester.tap(find.text(testTripHomeLabels.quickMemories));
    await tester.pumpAndSettle();

    expect(find.text(testTripHomeLabels.memoriesTitle), findsOneWidget);
  });
}

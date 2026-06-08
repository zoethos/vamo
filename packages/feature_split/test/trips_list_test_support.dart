import 'package:app_core/app_core.dart';
import 'package:drift/native.dart';
import 'package:feature_split/src/expenses/expense_models.dart';
import 'package:feature_split/src/expenses/expenses_providers.dart';
import 'package:feature_split/src/trips/trips_list_screen.dart';
import 'package:feature_split/src/trips/trips_models.dart';
import 'package:feature_split/src/trips/trips_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'trips_list_labels_test_support.dart';

class _StubAuthRepository extends AuthRepository {
  _StubAuthRepository()
      : super(
          SupabaseClient(
            'http://localhost',
            'anon-key',
            authOptions: const AuthClientOptions(autoRefreshToken: false),
          ),
        );

  @override
  User? get currentUser => null;

  @override
  bool get isSignedIn => false;

  @override
  Stream<AuthState> get authStateChanges => const Stream.empty();
}

List<Override> tripsListTestOverrides(
  List<TripSummary> trips, {
  AppDatabase? database,
}) {
  final db = database ?? AppDatabase.forTesting(NativeDatabase.memory());
  if (database == null) {
    addTearDown(db.close);
  }
  final client = SupabaseClient(
    'http://localhost',
    'anon-key',
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );

  return [
    appDatabaseProvider.overrideWithValue(db),
    supabaseClientProvider.overrideWithValue(client),
    analyticsProvider.overrideWithValue(DebugAnalytics()),
    authRepositoryProvider.overrideWith((ref) => _StubAuthRepository()),
    tripsSyncProvider.overrideWith((ref) async {}),
    tripsListProvider.overrideWith((ref) => Stream.value(trips)),
    pendingSyncCountProvider.overrideWith((ref) => Stream.value(0)),
    tripMembersForExpenseProvider.overrideWith(
      (ref, tripId) => Stream.value(const [
        TripMemberView(
          userId: 'owner-1',
          displayName: 'Owner',
          role: 'owner',
        ),
        TripMemberView(
          userId: 'member-2',
          displayName: 'Member',
          role: 'member',
        ),
      ]),
    ),
  ];
}

Widget pumpTripsListScreen({
  required List<TripSummary> trips,
  TripsListScreenLabels? labels,
  ThemeData? theme,
}) {
  return ProviderScope(
    overrides: tripsListTestOverrides(trips),
    child: MaterialApp(
      theme: theme ?? AppTheme.light,
      home: TripsListScreen(labels: labels ?? testTripsListLabels),
    ),
  );
}

Future<void> tapFilter(WidgetTester tester, String label) async {
  await tester.tap(find.widgetWithText(FilterChip, label));
  await tester.pumpAndSettle();
}

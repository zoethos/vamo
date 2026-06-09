import 'package:app_core/app_core.dart';
import 'package:feature_split/src/expenses/expense_models.dart';
import 'package:feature_split/src/expenses/expenses_providers.dart';
import 'package:feature_split/src/invites/contact_invite_gateway.dart';
import 'package:feature_split/src/invites/invites_repository.dart';
import 'package:feature_split/src/trips/members_tab.dart';
import 'package:feature_split/src/trips/trip_members_screen.dart';
import 'package:feature_split/src/trips/trips_models.dart';
import 'package:feature_split/src/trips/trips_providers.dart';
import 'package:feature_split/src/sync/trip_realtime_binding.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'invite_labels_test_support.dart';
import 'trip_home_labels_test_support.dart';

const membersTabTestTripId = 'trip-members-test';

final membersTabTestDetail = TripDetail(
  id: membersTabTestTripId,
  name: 'Test trip',
  baseCurrency: 'EUR',
  ownerId: 'owner',
  lifecycle: 'active',
);

class FakeInvitesRepository extends InvitesRepository {
  FakeInvitesRepository(Analytics analytics)
      : super(
          client: SupabaseClient(
            'http://localhost',
            'test-anon-key',
            authOptions: const AuthClientOptions(autoRefreshToken: false),
          ),
          analytics: analytics,
        );

  @override
  Future<String> getOrCreateInviteToken(String tripId) async => 'test-token';
}

Widget pumpMembersTab({
  required ContactInviteGateway gateway,
  ThemeData? theme,
}) {
  return MediaQuery(
    data: const MediaQueryData(size: Size(480, 900)),
    child: ProviderScope(
      overrides: [
        analyticsProvider.overrideWithValue(DebugAnalytics()),
        invitesRepositoryProvider.overrideWith(
          (ref) => FakeInvitesRepository(ref.read(analyticsProvider)),
        ),
        tripMembersForExpenseProvider(membersTabTestTripId).overrideWith(
          (ref) => Stream.value([
            TripMemberView(
              userId: 'owner',
              displayName: 'Owner',
              role: 'owner',
            ),
          ]),
        ),
        tripDetailProvider(membersTabTestTripId).overrideWith(
          (ref) => Stream.value(membersTabTestDetail),
        ),
        tripRealtimeBindingProvider(membersTabTestTripId).overrideWith(
          (ref) {},
        ),
        currentUserProvider.overrideWith(
          (ref) => User(
            id: 'owner',
            appMetadata: const {},
            userMetadata: const {},
            aud: 'authenticated',
            createdAt: DateTime.utc(2026, 1, 1).toIso8601String(),
          ),
        ),
      ],
      child: MaterialApp(
        theme: theme ?? AppTheme.light,
        home: Scaffold(
          body: MembersTab(
            tripId: membersTabTestTripId,
            inviteLabels: testInviteLabels,
            contactInviteGateway: gateway,
          ),
        ),
      ),
    ),
  );
}

Widget pumpMembersScreen({
  required ContactInviteGateway gateway,
  ThemeData? theme,
}) {
  return MediaQuery(
    data: const MediaQueryData(size: Size(480, 900)),
    child: ProviderScope(
      overrides: [
        analyticsProvider.overrideWithValue(DebugAnalytics()),
        invitesRepositoryProvider.overrideWith(
          (ref) => FakeInvitesRepository(ref.read(analyticsProvider)),
        ),
        tripMembersForExpenseProvider(membersTabTestTripId).overrideWith(
          (ref) => Stream.value([
            TripMemberView(
              userId: 'owner',
              displayName: 'Owner',
              role: 'owner',
            ),
          ]),
        ),
        tripDetailProvider(membersTabTestTripId).overrideWith(
          (ref) => Stream.value(membersTabTestDetail),
        ),
        tripRealtimeBindingProvider(membersTabTestTripId).overrideWith(
          (ref) {},
        ),
        currentUserProvider.overrideWith(
          (ref) => User(
            id: 'owner',
            appMetadata: const {},
            userMetadata: const {},
            aud: 'authenticated',
            createdAt: DateTime.utc(2026, 1, 1).toIso8601String(),
          ),
        ),
      ],
      child: MaterialApp(
        theme: theme ?? AppTheme.light,
        home: TripMembersScreen(
          tripId: membersTabTestTripId,
          tripHomeLabels: testTripHomeLabels,
          inviteLabels: testInviteLabels,
        ),
      ),
    ),
  );
}

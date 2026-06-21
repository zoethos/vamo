import 'package:app_core/app_core.dart';
import 'package:feature_split/feature_split.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'trips_list_labels_test_support.dart';
import 'trips_list_test_support.dart';

NotificationLabels _testNotificationLabels() => const NotificationLabels(
      inboxTitle: 'Notifications',
      emptyTitle: 'All caught up',
      emptySubtitle: 'Nothing here',
      markAllRead: 'Mark all read',
      unreadBadge: _unreadBadge,
      typeCloseNotice: 'Trip closing',
      typeCloseReminder: 'Close reminder',
      typeDeemedClosed: 'Trip closed',
      typeSettleNudge: 'Settle up',
      typeWrappedTrip: 'Trip wrapped',
      typePremiumGate: 'Vamo Plus',
      typeGeneric: 'Notice',
    );

String _unreadBadge(int count) => '$count unread';

final _sampleTrip = TripSummary(
  id: 'trip-1',
  name: 'Amalfi',
  startDate: '2099-07-10',
  endDate: '2099-07-17',
  baseCurrency: 'EUR',
);

void main() {
  testWidgets('bell shows unread badge from provider', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...tripsListTestOverrides([_sampleTrip]),
          unreadNotificationCountProvider.overrideWith(
            (ref) => Stream.value(3),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: TripsListScreen(labels: testTripsListLabels),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('bell tap opens notifications inbox route', (tester) async {
    final router = GoRouter(
      initialLocation: AppRoutes.trips,
      routes: [
        GoRoute(
          path: AppRoutes.trips,
          builder: (context, state) => TripsListScreen(
            labels: testTripsListLabels,
          ),
        ),
        GoRoute(
          path: AppRoutes.notifications,
          builder: (context, state) => NotificationsInboxScreen(
            labels: _testNotificationLabels(),
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...tripsListTestOverrides([_sampleTrip]),
          unreadNotificationCountProvider.overrideWith(
            (ref) => Stream.value(0),
          ),
          notificationsProvider.overrideWith((ref) => Stream.value(const [])),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light,
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byTooltip(testTripsListLabels.notificationsTooltip));
    await tester.pump();
    await tester.pump();

    expect(find.byType(NotificationsInboxScreen), findsOneWidget);
  });
}

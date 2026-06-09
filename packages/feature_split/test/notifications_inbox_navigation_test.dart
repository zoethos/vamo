import 'dart:io';

import 'package:app_core/app_core.dart';
import 'package:drift/native.dart';
import 'package:feature_split/feature_split.dart';
import 'package:feature_split/src/notifications/notification_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
      typeGeneric: 'Notice',
    );

String _unreadBadge(int count) => '$count unread';

NotificationItem _notification({required String route}) {
  return NotificationItem(
    id: 'notice-1',
    userId: 'user-1',
    tripId: 'trip-1',
    type: 'close_notice',
    title: 'Trip is closing',
    body: 'Review balances before auto-close.',
    route: route,
    createdAt: DateTime.utc(2099, 1, 1),
    readAt: DateTime.utc(2099, 1, 1),
  );
}

class _StubNotificationsRepository extends NotificationsRepository {
  _StubNotificationsRepository()
      : super(
          db: AppDatabase.forTesting(NativeDatabase.memory()),
          client: SupabaseClient(
            'http://localhost',
            'anon-key',
            authOptions: const AuthClientOptions(autoRefreshToken: false),
          ),
        );

  @override
  Future<void> markRead(String id) async {}
}

GoRouter _shellRouter(GlobalKey<NavigatorState> rootNavigatorKey) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: AppRoutes.notifications,
    routes: [
      GoRoute(
        path: AppRoutes.notifications,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => NotificationsInboxScreen(
          labels: _testNotificationLabels(),
        ),
      ),
      GoRoute(
        path: '/trips/:tripId/close-report',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => Scaffold(
          body: Center(
            child: Text('close-report-${state.pathParameters['tripId']}'),
          ),
        ),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => navigationShell,
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.trips,
                builder: (context, state) => const Scaffold(
                  body: Center(child: Text('trips-dest')),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.activity,
                builder: (context, state) => const Scaffold(
                  body: Center(child: Text('activity-dest')),
                ),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

Future<GoRouter> _pumpInbox(
  WidgetTester tester, {
  required List<NotificationItem> notifications,
}) async {
  final rootNavigatorKey = GlobalKey<NavigatorState>();
  final router = _shellRouter(rootNavigatorKey);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        notificationsProvider.overrideWith((ref) => Stream.value(notifications)),
        notificationsRepositoryProvider.overrideWith(
          (ref) => _StubNotificationsRepository(),
        ),
      ],
      child: MaterialApp.router(
        theme: AppTheme.light,
        routerConfig: router,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return router;
}

void main() {
  testWidgets('tapping notification to trips shell root uses go', (tester) async {
    final router = await _pumpInbox(
      tester,
      notifications: [_notification(route: AppRoutes.trips)],
    );

    await tester.tap(find.text('Trip is closing'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('trips-dest'), findsOneWidget);
    expect(router.state.matchedLocation, AppRoutes.trips);
  });

  testWidgets('tapping notification tile navigates via go, not push', (tester) async {
    const tripId = 'trip-1';
    final router = await _pumpInbox(
      tester,
      notifications: [
        _notification(route: AppRoutes.tripCloseReport(tripId)),
      ],
    );

    await tester.tap(find.text('Trip is closing'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('close-report-$tripId'), findsOneWidget);
    expect(
      router.state.matchedLocation,
      AppRoutes.tripCloseReport(tripId),
    );
  });

  test('navigateToNotificationRoute uses go not push', () {
    final source = File(
      'lib/src/notifications/notifications_inbox_screen.dart',
    ).readAsStringSync();
    expect(source, contains('context.go(route)'));
    expect(source, isNot(contains('context.push(route)')));
  });
}

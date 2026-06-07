import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:feature_split/feature_split.dart';
import 'package:go_router/go_router.dart';

import 'l10n/app_localizations.dart';
import 'router_redirect.dart';
import 'split_labels.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();

/// The app's GoRouter. Lives in the app shell (not app_core) so it can wire
/// feature screens to paths while app_core stays feature-agnostic.
final routerProvider = Provider<GoRouter>((ref) {
  final authRepo = ref.watch(authRepositoryProvider);
  final analytics = ref.watch(analyticsProvider);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: AppRoutes.trips,
    observers: [VamoNavigationObserver(analytics)],
    refreshListenable: GoRouterRefreshStream(authRepo.authStateChanges),
    redirect: (context, state) {
      return resolveRouterRedirect(
        uri: state.uri,
        matchedLocation: state.matchedLocation,
        queryParameters: state.uri.queryParameters,
        isSignedIn: authRepo.isSignedIn,
        onPendingInvite: (token, channel) {
          ref.read(pendingInviteTokenProvider.notifier).state = token;
          ref.read(pendingInviteChannelProvider.notifier).state = channel;
        },
      );
    },
    onException: (context, state, router) {
      final shape = routeNotFoundLocationShape(state);
      analytics.capture(
        VamoEvent.routeNotFound,
        properties: {'location_shape': shape},
      );
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text(routeNotFoundUserMessage)),
      );
      router.go(AppRoutes.trips);
    },
    routes: [
      GoRoute(
        path: AppRoutes.join,
        name: 'join',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final token = inviteTokenFromLocation(
            state.matchedLocation,
            query: state.uri.queryParameters,
          );
          final channel = inviteChannelFromQuery(state.uri.queryParameters);
          ref.read(pendingInviteChannelProvider.notifier).state = channel;
          final l10n = AppLocalizations.of(context);
          return JoinTripScreen(
            token: token ?? '',
            labels: SplitLabels.invite(l10n),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.auth,
        name: 'auth',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final l10n = AppLocalizations.of(context);
          return AuthScreen(
            inviteLabels: SplitLabels.invite(l10n),
            authLabels: SplitLabels.auth(l10n),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.loginCallback,
        name: 'login_callback',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const AuthCallbackScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          final l10n = AppLocalizations.of(context);
          return MainShell(
            navigationShell: navigationShell,
            labels: SplitLabels.shell(l10n),
            expensesFabLabels: SplitLabels.expensesFab(l10n),
          );
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.trips,
                name: 'trips',
                builder: (context, state) {
                  final l10n = AppLocalizations.of(context);
                  return TripsListScreen(labels: SplitLabels.trips(l10n));
                },
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.activity,
                name: 'activity',
                builder: (context, state) {
                  final l10n = AppLocalizations.of(context);
                  return ActivityScreen(labels: SplitLabels.activity(l10n));
                },
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.expenses,
                name: 'expenses',
                builder: (context, state) {
                  final l10n = AppLocalizations.of(context);
                  return ExpensesListScreen(labels: SplitLabels.expenses(l10n));
                },
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.profile,
                name: 'profile',
                builder: (context, state) {
                  final l10n = AppLocalizations.of(context);
                  return ProfileScreen(labels: SplitLabels.profile(l10n));
                },
                routes: [
                  GoRoute(
                    path: 'suggest',
                    name: 'suggest_feature',
                    parentNavigatorKey: _rootNavigatorKey,
                    builder: (context, state) => const SuggestFeatureScreen(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.tripCreate,
        name: 'create_trip',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final l10n = AppLocalizations.of(context);
          return CreateTripScreen(labels: SplitLabels.createTrip(l10n));
        },
      ),
      GoRoute(
        path: '/trips/:tripId',
        name: 'trip_home',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final id = state.pathParameters['tripId']!;
          final l10n = AppLocalizations.of(context);
          return TripHomeScreen(
            tripId: id,
            initialTab: state.uri.queryParameters['tab'],
            inviteLabels: SplitLabels.invite(l10n),
            planLabels: SplitLabels.plan(l10n),
            governanceLabels: SplitLabels.governance(l10n),
            budgetLabels: SplitLabels.budget(l10n),
            lifecycleLabels: SplitLabels.lifecycle(l10n),
            tripHomeLabels: SplitLabels.tripHome(l10n),
            balancesLabels: SplitLabels.balances(l10n),
          );
        },
        routes: [
          GoRoute(
            path: 'settings',
            name: 'trip_settings',
            parentNavigatorKey: _rootNavigatorKey,
            builder: (context, state) {
              final id = state.pathParameters['tripId']!;
              final l10n = AppLocalizations.of(context);
              return TripSettingsScreen(
                tripId: id,
                labels: SplitLabels.budget(l10n),
              );
            },
          ),
          GoRoute(
            path: 'expenses/new',
            name: 'add_expense',
            parentNavigatorKey: _rootNavigatorKey,
            builder: (context, state) {
              final id = state.pathParameters['tripId']!;
              final l10n = AppLocalizations.of(context);
              return AddExpenseScreen(
                tripId: id,
                labels: SplitLabels.governance(l10n),
                screenLabels: SplitLabels.addExpense(l10n),
              );
            },
          ),
          GoRoute(
            path: 'expenses/propose',
            name: 'propose_expense',
            parentNavigatorKey: _rootNavigatorKey,
            builder: (context, state) {
              final id = state.pathParameters['tripId']!;
              final l10n = AppLocalizations.of(context);
              return AddExpenseScreen(
                tripId: id,
                mode: AddExpenseMode.proposed,
                labels: SplitLabels.governance(l10n),
                screenLabels: SplitLabels.addExpense(l10n),
              );
            },
          ),
          GoRoute(
            path: 'snapshot',
            name: 'snapshot',
            parentNavigatorKey: _rootNavigatorKey,
            builder: (context, state) {
              final id = state.pathParameters['tripId']!;
              return SnapshotShareScreen(tripId: id);
            },
          ),
          GoRoute(
            path: 'capture/note',
            name: 'capture_note',
            parentNavigatorKey: _rootNavigatorKey,
            builder: (context, state) {
              final id = state.pathParameters['tripId']!;
              return AddCaptureNoteScreen(tripId: id);
            },
          ),
        ],
      ),
    ],
  );
});

import 'package:app_core/app_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:feature_split/feature_split.dart';
import 'package:go_router/go_router.dart';

/// The app's GoRouter. Lives in the app shell (not app_core) so it can wire
/// feature screens to paths while app_core stays feature-agnostic.
final routerProvider = Provider<GoRouter>((ref) {
  final authRepo = ref.watch(authRepositoryProvider);
  final analytics = ref.watch(analyticsProvider);

  return GoRouter(
    initialLocation: AppRoutes.trips,
    observers: [VamoNavigationObserver(analytics)],
    refreshListenable: GoRouterRefreshStream(authRepo.authStateChanges),
    redirect: (context, state) {
      if (AuthUrls.isAuthCallback(state.uri)) {
        return AuthUrls.inAppLoginCallbackLocation(state.uri);
      }
      final location = state.matchedLocation;
      if (location.startsWith('${AuthUrls.appScheme}://')) {
        final parsed = Uri.tryParse(location);
        if (parsed != null && AuthUrls.isAuthCallback(parsed)) {
          return AuthUrls.inAppLoginCallbackLocation(parsed);
        }
      }

      final token = inviteTokenFromLocation(
        state.matchedLocation,
        query: state.uri.queryParameters,
      );
      if (token != null && !authRepo.isSignedIn) {
        ref.read(pendingInviteTokenProvider.notifier).state = token;
        return AppRoutes.auth;
      }

      return authRedirect(
        isSignedIn: authRepo.isSignedIn,
        location: state.matchedLocation,
      );
    },
    routes: [
      GoRoute(
        path: AppRoutes.join,
        name: 'join',
        builder: (context, state) {
          final token = inviteTokenFromLocation(
            state.matchedLocation,
            query: state.uri.queryParameters,
          );
          return JoinTripScreen(token: token ?? '');
        },
      ),
      GoRoute(
        path: AppRoutes.auth,
        name: 'auth',
        builder: (context, state) => const AuthScreen(),
      ),
      GoRoute(
        path: AppRoutes.loginCallback,
        name: 'login_callback',
        builder: (context, state) => const AuthCallbackScreen(),
      ),
      GoRoute(
        path: AppRoutes.settings,
        name: 'settings',
        builder: (context, state) => const SettingsScreen(),
        routes: [
          GoRoute(
            path: 'suggest',
            name: 'suggest_feature',
            builder: (context, state) => const SuggestFeatureScreen(),
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.trips,
        name: 'trips',
        builder: (context, state) => const TripsListScreen(),
        routes: [
          GoRoute(
            path: 'create',
            name: 'create_trip',
            builder: (context, state) => const CreateTripScreen(),
          ),
          GoRoute(
            path: ':tripId',
            name: 'trip_home',
            builder: (context, state) {
              final id = state.pathParameters['tripId']!;
              return TripHomeScreen(tripId: id);
            },
            routes: [
              GoRoute(
                path: 'expenses/new',
                name: 'add_expense',
                builder: (context, state) {
                  final id = state.pathParameters['tripId']!;
                  return AddExpenseScreen(tripId: id);
                },
              ),
              GoRoute(
                path: 'snapshot',
                name: 'snapshot',
                builder: (context, state) {
                  final id = state.pathParameters['tripId']!;
                  return SnapshotShareScreen(tripId: id);
                },
              ),
              GoRoute(
                path: 'capture/note',
                name: 'capture_note',
                builder: (context, state) {
                  final id = state.pathParameters['tripId']!;
                  return AddCaptureNoteScreen(tripId: id);
                },
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

import 'dart:async';

import 'package:flutter/foundation.dart';

/// Canonical route paths. Features and the app shell reference these instead
/// of string literals.
abstract final class AppRoutes {
  static const auth = '/auth';
  static const trips = '/trips';
  static const activity = '/activity';
  static const expenses = '/expenses';
  static const profile = '/profile';
  static const settings = '/profile';
  static const profileCompletion = '/profile/complete';
  static const suggestFeature = '/profile/suggest';
  static const tripCreate = '/trips/create';

  static const notifications = '/notifications';
  static String trip(String id) => '/trips/$id';
  static String tripExpenses(String tripId) => '/trips/$tripId/expenses';
  static String tripPlan(String tripId) => '/trips/$tripId/plan';
  static String tripBalances(String tripId) => '/trips/$tripId/balances';
  static String tripMembers(String tripId) => '/trips/$tripId/members';
  static String tripAddExpense(String tripId) => '/trips/$tripId/expenses/new';
  static String tripProposeExpense(String tripId) =>
      '/trips/$tripId/expenses/propose';
  static String tripSettings(String tripId) => '/trips/$tripId/settings';
  static String tripSnapshot(String tripId) => '/trips/$tripId/snapshot';
  static String tripCloseReport(String tripId) => '/trips/$tripId/close-report';
  static String tripAddCaptureNote(String tripId) =>
      '/trips/$tripId/capture/note';
  static String tripMemories(String tripId) => '/trips/$tripId/memories';
  static const join = '/join';
  static const loginCallback = '/login-callback';
}

/// Bridges a Supabase auth [Stream] to GoRouter's `refreshListenable`, so the
/// router re-evaluates its redirect whenever sign-in state changes.
class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _subscription = stream.asBroadcastStream().listen(
          (_) => notifyListeners(),
          onError: (_, __) => notifyListeners(),
        );
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

/// Pure redirect rule shared by the router: unauthenticated users go to the
/// auth screen; authenticated users are kept out of it. Returns the path to
/// redirect to, or null to stay put.
String? authRedirect({required bool isSignedIn, required String location}) {
  if (location.startsWith(AppRoutes.loginCallback)) return null;

  final onAuthScreen = location == AppRoutes.auth;
  if (!isSignedIn) return onAuthScreen ? null : AppRoutes.auth;
  if (onAuthScreen) return AppRoutes.trips;
  return null;
}

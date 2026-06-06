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
  static const suggestFeature = '/profile/suggest';
  static const tripCreate = '/trips/create';

  static String trip(String id) => '/trips/$id';
  static String tripAddExpense(String tripId) => '/trips/$tripId/expenses/new';
  static String tripProposeExpense(String tripId) =>
      '/trips/$tripId/expenses/propose';
  static String tripSnapshot(String tripId) => '/trips/$tripId/snapshot';
  static String tripAddCaptureNote(String tripId) =>
      '/trips/$tripId/capture/note';
  static const join = '/join';
  static const loginCallback = '/login-callback';
}

/// Bridges a Supabase auth [Stream] to GoRouter's `refreshListenable`, so the
/// router re-evaluates its redirect whenever sign-in state changes.
class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _subscription = stream.asBroadcastStream().listen((_) => notifyListeners());
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

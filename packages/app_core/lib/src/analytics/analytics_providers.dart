import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_providers.dart';
import '../env/env.dart';
import 'analytics.dart';
import 'posthog_analytics.dart';

final analyticsProvider = Provider<Analytics>((ref) {
  if (Env.posthogApiKey.isNotEmpty) {
    return PosthogAnalytics();
  }
  return DebugAnalytics();
});

/// Identifies the user on sign-in and resets on sign-out. Mount once in the app shell.
final analyticsLifecycleProvider = Provider<void>((ref) {
  final analytics = ref.watch(analyticsProvider);

  ref.listen(authStateChangesProvider, (prev, next) {
    final wasSignedIn = prev?.valueOrNull?.session != null;
    final userId = next.valueOrNull?.session?.user.id;
    if (userId != null && !wasSignedIn) {
      analytics.identify(userId);
    } else if (userId == null && wasSignedIn) {
      analytics.reset();
    }
  });

  final session = ref.read(authStateChangesProvider).valueOrNull?.session;
  if (session != null) {
    analytics.identify(session.user.id);
  }
});

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_providers.dart';
import 'profile_models.dart';
import 'profile_repository.dart';

/// Current user's profile; refreshes on sign-in and after settings save.
final userProfileProvider = FutureProvider<UserProfile>((ref) async {
  ref.watch(authStateChangesProvider);
  if (!ref.watch(isSignedInProvider)) {
    throw StateError('Not signed in');
  }
  return ref.watch(profileRepositoryProvider).fetchCurrent();
});

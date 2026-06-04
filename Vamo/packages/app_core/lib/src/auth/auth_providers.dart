import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase/supabase_providers.dart';
import 'auth_repository.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(supabaseClientProvider));
});

/// Streams Supabase auth changes. The router watches this to redirect.
final authStateChangesProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges;
});

/// Cheap synchronous read of "is there a session right now?".
///
/// Recomputed whenever [authStateChangesProvider] emits.
final isSignedInProvider = Provider<bool>((ref) {
  ref.watch(authStateChangesProvider);
  return ref.watch(authRepositoryProvider).isSignedIn;
});

/// The current authenticated user, or null.
final currentUserProvider = Provider<User?>((ref) {
  ref.watch(authStateChangesProvider);
  return ref.watch(authRepositoryProvider).currentUser;
});

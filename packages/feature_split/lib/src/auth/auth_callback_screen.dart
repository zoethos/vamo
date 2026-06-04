import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../invites/invite_flow.dart';

/// Waiting room for Supabase magic-link / OAuth redirects.
///
/// [Supabase.initialize] keeps `detectSessionInUri: true` (the default), so
/// supabase_flutter exchanges the one-time PKCE code from the deep link on its
/// own. This screen must not call [AuthClient.getSessionFromUrl] — a second
/// exchange races the first and intermittently fails with "flow state not found".
class AuthCallbackScreen extends ConsumerStatefulWidget {
  const AuthCallbackScreen({super.key});

  @override
  ConsumerState<AuthCallbackScreen> createState() => _AuthCallbackScreenState();
}

class _AuthCallbackScreenState extends ConsumerState<AuthCallbackScreen> {
  StreamSubscription<AuthState>? _authSub;
  Timer? _timeout;
  bool _wasSignedInOnArrival = false;
  String? _userIdOnArrival;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _waitForSession());
  }

  void _waitForSession() {
    _wasSignedInOnArrival = ref.read(isSignedInProvider);
    _userIdOnArrival = ref.read(currentUserProvider)?.id;

    if (!_wasSignedInOnArrival && ref.read(isSignedInProvider)) {
      unawaited(_continueSignedIn());
      return;
    }

    _authSub = ref.read(authRepositoryProvider).authStateChanges.listen((state) {
      if (state.event != AuthChangeEvent.signedIn || !mounted) return;
      final newUserId = state.session?.user.id;
      if (!_wasSignedInOnArrival || newUserId != _userIdOnArrival) {
        unawaited(_continueSignedIn());
      }
    });

    final timeout = _wasSignedInOnArrival
        ? const Duration(seconds: 5)
        : const Duration(seconds: 30);
    _timeout = Timer(timeout, () {
      if (!mounted) return;
      if (ref.read(isSignedInProvider)) {
        if (_wasSignedInOnArrival) {
          unawaited(_failWithExistingSession());
        } else {
          unawaited(_continueSignedIn());
        }
      } else {
        unawaited(_failWithoutSession());
      }
    });
  }

  Future<void> _continueSignedIn() async {
    _cleanup();
    if (!mounted) return;
    await tryConsumePendingInvite(ref: ref, context: context);
    if (!mounted) return;
    context.go(AppRoutes.trips);
  }

  Future<void> _failWithExistingSession() async {
    _cleanup();
    if (!mounted) return;
    final label = _signedInAsLabel();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'That sign-in link was for a different device or account — '
          "you're still signed in as $label.",
        ),
      ),
    );
    context.go(AppRoutes.trips);
  }

  Future<void> _failWithoutSession() async {
    _cleanup();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'This link was started on another device. '
          'Enter the 6-digit code from the email instead.',
        ),
      ),
    );
    context.go(AppRoutes.auth);
  }

  String _signedInAsLabel() {
    final user = ref.read(currentUserProvider);
    if (user == null) return 'your account';
    final meta = user.userMetadata?['display_name'];
    if (meta is String && meta.isNotEmpty) return meta;
    final email = user.email;
    if (email != null && email.isNotEmpty) {
      return email.split('@').first;
    }
    return 'your account';
  }

  void _cleanup() {
    _timeout?.cancel();
    _timeout = null;
    unawaited(_authSub?.cancel());
    _authSub = null;
  }

  @override
  void dispose() {
    _cleanup();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}

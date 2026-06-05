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
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _waitForSession());
  }

  void _waitForSession() {
    if (_hasSession()) {
      unawaited(_continueSignedIn());
      return;
    }

    _authSub = ref.read(authRepositoryProvider).authStateChanges.listen((state) {
      if (state.event == AuthChangeEvent.signedIn && mounted) {
        unawaited(_continueSignedIn());
      }
    });

    _timeout = Timer(const Duration(seconds: 10), () {
      if (!mounted) return;
      if (_hasSession()) {
        unawaited(_continueSignedIn());
      } else {
        unawaited(_failWithoutSession());
      }
    });
  }

  bool _hasSession() => ref.read(authRepositoryProvider).currentSession != null;

  Future<void> _continueSignedIn() async {
    if (_finished || !_hasSession()) return;
    _finished = true;
    _cleanup();
    if (!mounted) return;
    await tryConsumePendingInvite(ref: ref, context: context);
    if (!mounted) return;
    context.go(AppRoutes.trips);
  }

  Future<void> _failWithoutSession() async {
    if (_finished) return;
    _cleanup();
    if (!mounted) return;
    if (_hasSession()) {
      await _continueSignedIn();
      return;
    }
    _finished = true;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          "Sign-in didn't complete — enter the 6-digit code from the email instead.",
        ),
      ),
    );
    context.go(AppRoutes.auth);
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

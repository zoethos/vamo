import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Slice 0 onboarding: email OTP wired end-to-end, with Apple/Google/phone as
/// the next surfaces to light up. On success the router redirects to /trips.
class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _emailController = TextEditingController();
  final _otpController = TextEditingController();
  bool _otpSent = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _run(
    Future<void> Function() action, {
    required String authAction,
  }) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on AuthException catch (e) {
      ref.read(analyticsProvider).reportActionFailed(
            screen: 'auth',
            action: authAction,
            error: e,
          );
      setState(() => _error = formatActionFailureMessage(e));
    } catch (e) {
      ref.read(analyticsProvider).reportActionFailed(
            screen: 'auth',
            action: authAction,
            error: e,
          );
      setState(() => _error = formatActionFailureMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendCode() => _run(() async {
        final email = _emailController.text.trim();
        if (email.isEmpty) {
          setState(() => _error = 'Enter your email first.');
          return;
        }
        await ref.read(authRepositoryProvider).signInWithEmailOtp(email);
        if (mounted) setState(() => _otpSent = true);
      }, authAction: 'send_email_otp');

  Future<void> _verify() => _run(() async {
        await ref.read(authRepositoryProvider).verifyOtp(
              email: _emailController.text.trim(),
              token: _otpController.text.trim(),
            );
        // No navigation here — the router's auth redirect handles it.
      }, authAction: 'verify_email_otp');

  Future<void> _oauth(OAuthProvider provider) => _run(
        () => ref.read(authRepositoryProvider).signInWithOAuth(provider),
        authAction: 'oauth_${provider.name}',
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Vamo',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.displaySmall?.copyWith(
                        color: AppColors.tealDark,
                        fontWeight: FontWeight.w800,
                      )),
                  const SizedBox(height: 8),
                  Text('Si va?',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(color: AppColors.muted)),
                  const SizedBox(height: 36),
                  if (!_otpSent) ...[
                    TextField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        hintText: 'you@example.com',
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _busy ? null : _sendCode,
                      child: _busy
                          ? const _Spinner()
                          : const Text('Continue with email'),
                    ),
                  ] else ...[
                    Text('We sent a code to ${_emailController.text.trim()}',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _otpController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '6-digit code'),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _busy ? null : _verify,
                      child:
                          _busy ? const _Spinner() : const Text('Verify & continue'),
                    ),
                    TextButton(
                      onPressed: _busy ? null : () => setState(() => _otpSent = false),
                      child: const Text('Use a different email'),
                    ),
                  ],
                  const SizedBox(height: 24),
                  const Row(children: [
                    Expanded(child: Divider()),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text('or'),
                    ),
                    Expanded(child: Divider()),
                  ]),
                  const SizedBox(height: 24),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _oauth(OAuthProvider.apple),
                    icon: const Icon(Icons.apple),
                    label: const Text('Continue with Apple'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _oauth(OAuthProvider.google),
                    icon: const Icon(Icons.g_mobiledata, size: 28),
                    label: const Text('Continue with Google'),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 20),
                    Text(_error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: theme.colorScheme.error)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner();
  @override
  Widget build(BuildContext context) => const SizedBox(
        height: 22,
        width: 22,
        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
      );
}

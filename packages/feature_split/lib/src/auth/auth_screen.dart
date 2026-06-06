import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../invites/invite_labels.dart';
import '../invites/invite_qr_scanner.dart';

/// Slice 0 onboarding: email OTP wired end-to-end, with Apple/Google/phone as
/// the next surfaces to light up. On success the router redirects to /trips.
class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key, this.inviteLabels});

  final InviteLabels? inviteLabels;

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  static const _resendCooldownSeconds = 60;

  final _emailController = TextEditingController();
  final _otpController = TextEditingController();
  bool _otpSent = false;
  bool _busy = false;
  String? _error;
  int _resendCooldown = 0;
  Timer? _resendTimer;

  @override
  void dispose() {
    _resendTimer?.cancel();
    _emailController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  void _startResendCooldown() {
    _resendTimer?.cancel();
    setState(() => _resendCooldown = _resendCooldownSeconds);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendCooldown <= 1) {
        setState(() => _resendCooldown = 0);
        timer.cancel();
      } else {
        setState(() => _resendCooldown -= 1);
      }
    });
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
      setState(() => _error = actionFailureUserMessage(e));
    } catch (e) {
      ref.read(analyticsProvider).reportActionFailed(
            screen: 'auth',
            action: authAction,
            error: e,
          );
      setState(() => _error = actionFailureUserMessage(e));
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
        if (mounted) {
          setState(() => _otpSent = true);
          _startResendCooldown();
        }
      }, authAction: 'send_email_otp');

  Future<void> _resendCode() => _run(() async {
        await ref.read(authRepositoryProvider).signInWithEmailOtp(
              _emailController.text.trim(),
            );
        if (mounted) _startResendCooldown();
      }, authAction: 'resend_email_otp');

  Future<void> _verify() => _run(() async {
        await ref.read(authRepositoryProvider).verifyOtp(
              email: _emailController.text.trim(),
              token: _otpController.text.trim(),
            );
      }, authAction: 'verify_email_otp');

  Future<void> _oauth(OAuthProvider provider) => _run(
        () => ref.read(authRepositoryProvider).signInWithOAuth(provider),
        authAction: 'oauth_${provider.name}',
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Opacity(
            opacity: 0.35,
            child: Image.asset(
              BrandAssets.patternLight,
              fit: BoxFit.cover,
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: 28,
                  vertical: 32,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Image.asset(
                        BrandAssets.primaryMark,
                        height: 72,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'VAMO',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          color: AppColors.ink,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Si va?',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: AppColors.graphite,
                        ),
                      ),
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
                        Text(
                          'We sent a code to ${_emailController.text.trim()}',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _otpController,
                          keyboardType: TextInputType.number,
                          decoration:
                              const InputDecoration(labelText: '6-digit code'),
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _busy ? null : _verify,
                          child: _busy
                              ? const _Spinner()
                              : const Text('Verify & continue'),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: (_busy || _resendCooldown > 0)
                              ? null
                              : _resendCode,
                          child: Text(
                            _resendCooldown > 0
                                ? 'Send me a new code (${_resendCooldown}s)'
                                : 'Send me a new code',
                          ),
                        ),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => setState(() {
                                    _otpSent = false;
                                    _otpController.clear();
                                    _resendTimer?.cancel();
                                    _resendCooldown = 0;
                                  }),
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
                        onPressed:
                            _busy ? null : () => _oauth(OAuthProvider.apple),
                        icon: const Icon(Icons.apple),
                        label: const Text('Continue with Apple'),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed:
                            _busy ? null : () => _oauth(OAuthProvider.google),
                        icon: const Icon(Icons.g_mobiledata, size: 28),
                        label: const Text('Continue with Google'),
                      ),
                      if (widget.inviteLabels != null &&
                          isInviteQrScanSupported) ...[
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _busy
                              ? null
                              : () => showInviteQrScannerSheet(
                                    context: context,
                                    ref: ref,
                                    labels: widget.inviteLabels!,
                                  ),
                          icon: const Icon(Icons.qr_code_scanner_outlined),
                          label: Text(widget.inviteLabels!.scanQr),
                        ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 20),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
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
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          color: AppColors.ink,
        ),
      );
}

import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_identity.dart';
import 'auth_urls.dart';

/// Wraps Supabase Auth so the rest of the app never touches the SDK directly.
///
/// Vamo supports email OTP and Apple/Google OAuth.
///
/// Supabase automatically links a verified OAuth email to an existing user.
/// A differently-addressed identity, including an Apple Private Relay address,
/// can only be added from an existing session through [linkIdentity].
class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient _client;
  AuthIdentityProvider? _pendingIdentityLink;

  /// Emits on every sign-in / sign-out / token refresh.
  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  Session? get currentSession => _client.auth.currentSession;
  User? get currentUser => _client.auth.currentUser;
  bool get isSignedIn => currentSession != null;
  AuthIdentityProvider? get pendingIdentityLink => _pendingIdentityLink;

  bool get hasSupportedCurrentIdentity {
    final provider = currentUser?.appMetadata['provider'] as String?;
    return AuthIdentityProvider.fromSupabaseProvider(provider) != null;
  }

  /// Sends a magic-link / OTP to [email].
  Future<void> signInWithEmailOtp(String email) {
    return _client.auth.signInWithOtp(
      email: email,
      emailRedirectTo: AuthUrls.redirectUri,
    );
  }

  /// Verifies a 6-digit email OTP.
  Future<AuthResponse> verifyOtp({
    required String token,
    required String email,
  }) {
    return _client.auth.verifyOTP(
      token: token,
      type: OtpType.email,
      email: email,
    );
  }

  Future<bool> signInWithOAuth(OAuthProvider provider) {
    return _client.auth.signInWithOAuth(
      provider,
      redirectTo: AuthUrls.redirectUri,
    );
  }

  /// Returns the methods linked to the current Supabase user.
  Future<Set<AuthIdentityProvider>> linkedIdentityProviders() async {
    final identities = await _client.auth.getUserIdentities();
    return identities
        .map(
          (identity) =>
              AuthIdentityProvider.fromSupabaseProvider(identity.provider),
        )
        .whereType<AuthIdentityProvider>()
        .toSet();
  }

  /// Starts Supabase's manual identity-link flow for the current user.
  ///
  /// It intentionally cannot run before sign-in: linking must add a provider
  /// identity to an existing Vamo account, never create a second account.
  Future<bool> linkIdentity(AuthIdentityProvider provider) async {
    final oauthProvider = switch (provider) {
      AuthIdentityProvider.google => OAuthProvider.google,
      AuthIdentityProvider.apple => OAuthProvider.apple,
      AuthIdentityProvider.email => throw ArgumentError.value(
          provider,
          'provider',
          'Email is primary',
        ),
    };
    _pendingIdentityLink = provider;
    try {
      final launched = await _client.auth.linkIdentity(
        oauthProvider,
        redirectTo: AuthUrls.redirectUri,
      );
      if (!launched) _pendingIdentityLink = null;
      return launched;
    } on AuthException catch (error) {
      _pendingIdentityLink = null;
      if (_isManualLinkingUnavailable(error)) {
        throw const IdentityLinkUnavailableException();
      }
      rethrow;
    }
  }

  /// Waits for the redirect exchange to prove the requested identity is linked.
  ///
  /// A pre-existing session survives a manual-link redirect, so a session alone
  /// cannot be treated as successful linking.
  Future<bool> awaitPendingIdentityLink({
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final pending = _pendingIdentityLink;
    if (pending == null) return true;
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final linked = await linkedIdentityProviders();
      if (linked.contains(pending)) {
        _pendingIdentityLink = null;
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 350));
    }
    return false;
  }

  /// Rejects a session created through a method Vamo does not support before
  /// that session can accept a pending invite or create product state.
  void requireSupportedCurrentIdentity() {
    final provider = currentUser?.appMetadata['provider'] as String?;
    if (!hasSupportedCurrentIdentity) {
      throw UnsupportedAuthIdentityException(provider);
    }
  }

  static bool _isManualLinkingUnavailable(AuthException error) {
    final message = error.message.toLowerCase();
    final code = error.code?.toLowerCase();
    return code == 'manual_linking_disabled' ||
        message.contains('manual linking') ||
        message.contains('identity linking');
  }

  Future<void> signOut() => _client.auth.signOut();
}

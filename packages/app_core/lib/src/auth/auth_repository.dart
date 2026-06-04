import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_urls.dart';

/// Wraps Supabase Auth so the rest of the app never touches the SDK directly.
///
/// Wave 1 supports email/phone OTP and Apple/Google OAuth. The profile row is
/// created server-side by the `handle_new_user` trigger, so there is nothing
/// to do here on first sign-in.
class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient _client;

  /// Emits on every sign-in / sign-out / token refresh.
  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  Session? get currentSession => _client.auth.currentSession;
  User? get currentUser => _client.auth.currentUser;
  bool get isSignedIn => currentSession != null;

  /// Sends a magic-link / OTP to [email].
  Future<void> signInWithEmailOtp(String email) {
    return _client.auth.signInWithOtp(
      email: email,
      emailRedirectTo: AuthUrls.redirectUri,
    );
  }

  /// Sends an SMS OTP to [phone] (E.164, e.g. +14155550123).
  Future<void> signInWithPhoneOtp(String phone) {
    return _client.auth.signInWithOtp(phone: phone);
  }

  /// Verifies a 6-digit code for email or phone OTP.
  Future<AuthResponse> verifyOtp({
    required String token,
    String? email,
    String? phone,
  }) {
    return _client.auth.verifyOTP(
      token: token,
      type: phone != null ? OtpType.sms : OtpType.email,
      email: email,
      phone: phone,
    );
  }

  Future<bool> signInWithOAuth(OAuthProvider provider) {
    return _client.auth.signInWithOAuth(
      provider,
      redirectTo: AuthUrls.redirectUri,
    );
  }

  Future<void> signOut() => _client.auth.signOut();
}

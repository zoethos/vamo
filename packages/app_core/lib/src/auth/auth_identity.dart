/// Authentication methods Vamo intentionally supports for product access.
///
/// Supabase owns identity linking. Vamo only accepts the supported methods and
/// never treats an OAuth email as a stable provider identifier. In particular,
/// Apple is identified by the provider identity Supabase stores for the user.
enum AuthIdentityProvider {
  email('email', 'Email code'),
  google('google', 'Google'),
  apple('apple', 'Apple');

  const AuthIdentityProvider(this.supabaseProvider, this.label);

  final String supabaseProvider;
  final String label;

  static AuthIdentityProvider? fromSupabaseProvider(String? value) {
    for (final provider in values) {
      if (provider.supabaseProvider == value) return provider;
    }
    return null;
  }
}

/// Thrown before Vamo can use a session created through an unsupported method.
class UnsupportedAuthIdentityException implements Exception {
  const UnsupportedAuthIdentityException(this.provider);

  final String? provider;

  @override
  String toString() => 'UnsupportedAuthIdentityException($provider)';
}

/// Thrown when the server has not enabled authenticated identity linking.
///
/// The Profile surface remains safe to open in that configuration; it simply
/// tells the member that this optional account-hardening step is unavailable.
class IdentityLinkUnavailableException implements Exception {
  const IdentityLinkUnavailableException();

  @override
  String toString() => 'IdentityLinkUnavailableException()';
}

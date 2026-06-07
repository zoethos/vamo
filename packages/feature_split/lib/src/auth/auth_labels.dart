/// Localized copy for the auth / sign-in screen (S27).
class AuthLabels {
  const AuthLabels({
    required this.tagline,
    required this.emailLabel,
    required this.emailHint,
    required this.otpLabel,
    required this.codeSent,
    required this.continueWithEmail,
    required this.verifyAndContinue,
    required this.useDifferentEmail,
    required this.orDivider,
    required this.continueWithApple,
    required this.continueWithGoogle,
    required this.resendCode,
    required this.resendCodeCooldown,
  });

  final String tagline;
  final String emailLabel;
  final String emailHint;
  final String otpLabel;
  final String Function(String email) codeSent;
  final String continueWithEmail;
  final String verifyAndContinue;
  final String useDifferentEmail;
  final String orDivider;
  final String continueWithApple;
  final String continueWithGoogle;
  final String resendCode;
  final String Function(int seconds) resendCodeCooldown;
}

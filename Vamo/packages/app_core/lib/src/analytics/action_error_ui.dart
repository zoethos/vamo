import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'action_failure.dart';
import 'analytics_providers.dart';
import 'error_kind.dart';

/// User-facing copy keyed by [AnalyticsErrorKind] — never raw exception text.
String catalogueMessageForKind(AnalyticsErrorKind kind) {
  switch (kind) {
    case AnalyticsErrorKind.network:
      return 'Check your connection and try again.';
    case AnalyticsErrorKind.auth:
      return 'Sign in again to continue.';
    case AnalyticsErrorKind.server:
      return 'Something went wrong on our side. Try again in a moment.';
    case AnalyticsErrorKind.unknown:
      return 'Something went wrong. Try again.';
  }
}

const _otpAuthCodes = {
  'otp_expired',
  'invalid_otp',
  'otp_disabled',
  'validation_failed',
};

const _flowStateAuthCodes = {
  'flow_state_not_found',
  'flow_state_expired',
  'bad_code_verifier',
  'invalid_grant',
};

/// Friendly SnackBar / inline copy for a failed write or auth step.
String actionFailureUserMessage(Object error) {
  if (error is AuthException) {
    return _authUserMessage(error);
  }
  return catalogueMessageForKind(classifyActionFailureKind(error));
}

String _authUserMessage(AuthException error) {
  final code = error.code?.toLowerCase() ?? '';
  if (_otpAuthCodes.contains(code) || code.contains('otp')) {
    return "That code didn't match — try again";
  }
  if (_flowStateAuthCodes.contains(code) ||
      error.message.toLowerCase().contains('flow state')) {
    return 'This link was for a different device — use the 6-digit code';
  }
  return catalogueMessageForKind(AnalyticsErrorKind.auth);
}

/// [actionFailureUserMessage] plus an optional dev-only suffix.
String formatActionFailureMessage(Object error) {
  final base = actionFailureUserMessage(error);
  final suffix = _debugFailureSuffix(error);
  if (suffix == null) return base;
  return '$base$suffix';
}

String? _debugFailureSuffix(Object error) {
  if (!kDebugMode) return null;
  final code = sanitizeActionFailureCode(error);
  if (code.toUpperCase().contains('PGRST') ||
      code.toLowerCase().contains('postgrest')) {
    return ' (${classifyActionFailureKind(error).value})';
  }
  return ' ($code)';
}

/// Reports [VamoEvent.actionFailed] and shows a catalogued SnackBar.
void showActionError(
  BuildContext context,
  WidgetRef ref, {
  required String screen,
  required String action,
  required Object error,
}) {
  ref.read(analyticsProvider).reportActionFailed(
        screen: screen,
        action: action,
        error: error,
      );
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(formatActionFailureMessage(error))),
  );
}

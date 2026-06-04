import 'dart:async';

import 'package:http/http.dart' show ClientException;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../fx/fx_snapshot.dart';
import 'analytics.dart';
import 'error_kind.dart';

/// Classifies a write failure for [VamoEvent.actionFailed].
AnalyticsErrorKind classifyActionFailureKind(Object error) {
  if (error is AuthException) {
    if (error is AuthRetryableFetchException) {
      return AnalyticsErrorKind.network;
    }
    return AnalyticsErrorKind.auth;
  }
  if (error is PostgrestException) {
    final code = error.code;
    if (code != null && _postgrestAuthCodes.contains(code)) {
      return AnalyticsErrorKind.auth;
    }
    return AnalyticsErrorKind.server;
  }
  if (error is StorageException) {
    return _storageFailureKind(error);
  }
  if (error is FxRatesException) {
    return AnalyticsErrorKind.server;
  }
  if (error is TimeoutException || error is ClientException) {
    return AnalyticsErrorKind.network;
  }
  return AnalyticsErrorKind.unknown;
}

/// Sanitized failure code for analytics — never raw exception text.
String sanitizeActionFailureCode(Object error) {
  if (error is PostgrestException) {
    final code = error.code;
    if (code != null && _isSafeCode(code)) return code;
    return 'postgrest_error';
  }
  if (error is StorageException) {
    final status = error.statusCode;
    if (status != null && _isSafeCode(status)) return 'storage_$status';
    return 'storage_error';
  }
  if (error is AuthRetryableFetchException) {
    return 'network_auth_retry';
  }
  if (error is AuthException) {
    final code = error.code;
    if (code != null && _isSafeCode(code)) return code;
    final status = error.statusCode;
    if (status != null && _isSafeCode(status)) return 'auth_$status';
    return 'auth_error';
  }
  if (error is FxRatesException) {
    return 'fx_unavailable';
  }
  if (error is TimeoutException) {
    return 'network_timeout';
  }
  if (error is ClientException) {
    return 'network_client';
  }
  return 'unknown';
}

/// Fires [VamoEvent.actionFailed] for SnackBar-class write failures.
extension AnalyticsActionFailure on Analytics {
  void reportActionFailed({
    required String screen,
    required String action,
    required Object error,
  }) {
    capture(
      VamoEvent.actionFailed,
      properties: {
        'screen': screen,
        'action': action,
        'kind': classifyActionFailureKind(error).value,
        'code': sanitizeActionFailureCode(error),
      },
    );
  }
}

const _postgrestAuthCodes = {
  'PGRST301',
  '42501',
};

const _storageAuthStatusCodes = {'401', '403'};

AnalyticsErrorKind _storageFailureKind(StorageException error) {
  final status = error.statusCode;
  if (status != null && _storageAuthStatusCodes.contains(status)) {
    return AnalyticsErrorKind.auth;
  }
  return AnalyticsErrorKind.server;
}

bool _isSafeCode(String code) {
  if (code.isEmpty || code.length > 32) return false;
  return RegExp(r'^[A-Za-z0-9_]+$').hasMatch(code);
}

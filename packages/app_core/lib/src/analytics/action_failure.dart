import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show DriftWrappedException, InvalidDataException;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' show ClientException;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../fx/fx_snapshot.dart';
import 'analytics.dart';
import 'error_kind.dart';

enum ActionFailureSeverity {
  failure('failure'),
  degraded('degraded');

  const ActionFailureSeverity(this.value);
  final String value;
}

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
  if (_isDriftOrSqliteException(error)) {
    return AnalyticsErrorKind.db;
  }
  if (error is FileSystemException) {
    return AnalyticsErrorKind.file;
  }
  if (_isAppFailure(error)) {
    return AnalyticsErrorKind.app;
  }
  if (error is TimeoutException || error is ClientException) {
    return AnalyticsErrorKind.network;
  }
  return AnalyticsErrorKind.unknown;
}

/// Sanitized failure code for analytics — never raw exception text.
String sanitizeActionFailureCode(Object error) {
  if (error is PostgrestException) {
    if (_isPostgrestFunctionNotFound(error)) {
      return 'postgrest_function_not_found';
    }
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
  if (_isDriftOrSqliteException(error)) {
    return 'db_error';
  }
  if (error is FileSystemException) {
    return 'file_error';
  }
  if (_isAppFailure(error)) {
    return _appFailureCode(error);
  }
  if (error is TimeoutException) {
    return 'network_timeout';
  }
  if (error is ClientException) {
    return 'network_client';
  }
  return 'unknown';
}

/// Logs raw details in debug and reports sanitized action failure telemetry.
void reportAndLog(
  Object error,
  StackTrace stackTrace, {
  required String screen,
  required String action,
  ActionFailureSeverity severity = ActionFailureSeverity.failure,
  Analytics? analytics,
}) {
  if (kDebugMode) {
    debugPrint(
      '[$screen/$action] severity=${severity.value} '
      'kind=${classifyActionFailureKind(error).value} '
      'code=${sanitizeActionFailureCode(error)}\n$error\n$stackTrace',
    );
  }
  analytics?.reportActionFailed(
    screen: screen,
    action: action,
    error: error,
    severity: severity,
  );
}

void debugBreadcrumb(
  String message, {
  required String screen,
  required String action,
  Map<String, Object?> details = const {},
}) {
  if (!kDebugMode) return;
  final suffix = details.isEmpty ? '' : ' $details';
  debugPrint('[$screen/$action] $message$suffix');
}

/// Fires [VamoEvent.actionFailed] for SnackBar-class write failures.
extension AnalyticsActionFailure on Analytics {
  void reportActionFailed({
    required String screen,
    required String action,
    required Object error,
    ActionFailureSeverity severity = ActionFailureSeverity.failure,
  }) {
    capture(
      VamoEvent.actionFailed,
      properties: {
        'screen': screen,
        'action': action,
        'severity': severity.value,
        'error_kind': classifyActionFailureKind(error).value,
        'error_code': sanitizeActionFailureCode(error),
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

bool _isPostgrestFunctionNotFound(PostgrestException error) {
  final code = error.code;
  if (code == 'PGRST202') return true;
  return error.message.toLowerCase().contains('could not find the function');
}

bool _isDriftOrSqliteException(Object error) {
  if (error is DriftWrappedException || error is InvalidDataException) {
    return true;
  }
  return _isSqliteException(error);
}

bool _isAppFailure(Object error) {
  if (error is FlutterError ||
      error is AssertionError ||
      error is StateError ||
      error is FormatException ||
      error is UnsupportedError ||
      error is TypeError ||
      error is NoSuchMethodError) {
    return true;
  }
  final type = error.runtimeType.toString();
  return type == 'NotInitializedError' ||
      type.contains('Navigator') ||
      type.contains('LateError') ||
      type.contains('LateInitializationError') ||
      type.contains('PlatformException') ||
      type.contains('MissingPluginException');
}

String _appFailureCode(Object error) {
  if (error is FlutterError) return 'flutter_error';
  if (error is AssertionError) return 'assertion_error';
  if (error is StateError) return 'state_error';
  if (error is FormatException) return 'format_error';
  if (error is UnsupportedError) return 'unsupported_error';
  if (error is TypeError) return 'type_error';
  if (error is NoSuchMethodError) return 'no_such_method';
  final type = error.runtimeType.toString();
  if (type == 'NotInitializedError') return 'app_not_initialized';
  if (type.contains('Navigator')) return 'navigator_error';
  if (type.contains('Late')) return 'late_init_error';
  if (type.contains('MissingPluginException')) return 'missing_plugin';
  if (type.contains('PlatformException')) return 'platform_exception';
  return 'app_error';
}

bool _isSqliteException(Object error) {
  final type = error.runtimeType.toString();
  return type == 'SqliteException' ||
      type == 'SqliteExceptionImpl' ||
      error.toString().contains('SqliteException');
}

import 'dart:async';
import 'dart:io';

import 'package:app_core/app_core.dart';
import 'package:drift/drift.dart' show DriftWrappedException;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' show ClientException;
import 'package:sqlite3/sqlite3.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('sanitizeActionFailureCode', () {
    test('returns PostgREST code when safe', () {
      expect(
        sanitizeActionFailureCode(
          const PostgrestException(
            message: 'Could not find the function public.create_trip',
            code: 'PGRST202',
          ),
        ),
        'postgrest_function_not_found',
      );
    });

    test('never returns raw exception message', () {
      expect(
        sanitizeActionFailureCode(
          const PostgrestException(message: 'secret internal detail'),
        ),
        'postgrest_error',
      );
    });

    test('maps AuthException to auth code or status', () {
      expect(
        sanitizeActionFailureCode(
          const AuthException('JWT expired',
              statusCode: '401', code: 'invalid_jwt'),
        ),
        'invalid_jwt',
      );
    });

    test('maps FxRatesException to fx_unavailable', () {
      expect(
        sanitizeActionFailureCode(FxRatesException('edge down')),
        'fx_unavailable',
      );
    });

    test('maps network errors to stable codes', () {
      expect(
        sanitizeActionFailureCode(TimeoutException('slow')),
        'network_timeout',
      );
      expect(
        sanitizeActionFailureCode(ClientException('offline')),
        'network_client',
      );
      expect(
        sanitizeActionFailureCode(AuthRetryableFetchException()),
        'network_auth_retry',
      );
    });

    test('maps StorageException to storage status codes', () {
      expect(
        sanitizeActionFailureCode(
          const StorageException('denied', statusCode: '403'),
        ),
        'storage_403',
      );
      expect(
        sanitizeActionFailureCode(
          const StorageException('unavailable'),
        ),
        'storage_error',
      );
    });

    test('maps local and framework failures to stable codes', () {
      expect(
        sanitizeActionFailureCode(const FileSystemException('nope')),
        'file_error',
      );
      expect(
        sanitizeActionFailureCode(
          DriftWrappedException(
              message: 'bad statement', cause: StateError('x')),
        ),
        'db_error',
      );
      expect(sanitizeActionFailureCode(StateError('bad state')), 'state_error');
      expect(
        sanitizeActionFailureCode(FlutterError('layout failed')),
        'flutter_error',
      );
      expect(
        sanitizeActionFailureCode(NotInitializedError()),
        'app_not_initialized',
      );
    });

    test('unknown errors collapse to unknown', () {
      expect(sanitizeActionFailureCode(Exception('oops')), 'unknown');
    });
  });

  group('classifyActionFailureKind', () {
    test('PostgREST missing RPC is server', () {
      expect(
        classifyActionFailureKind(
          const PostgrestException(message: 'missing', code: 'PGRST202'),
        ),
        AnalyticsErrorKind.server,
      );
    });

    test('PostgREST permission denied is auth', () {
      expect(
        classifyActionFailureKind(
          const PostgrestException(
            message: 'only_owner_may_delete',
            code: '42501',
          ),
        ),
        AnalyticsErrorKind.auth,
      );
    });

    test('AuthException is auth unless retryable fetch', () {
      expect(
        classifyActionFailureKind(
            const AuthException('bad token', code: '401')),
        AnalyticsErrorKind.auth,
      );
      expect(
        classifyActionFailureKind(AuthRetryableFetchException()),
        AnalyticsErrorKind.network,
      );
    });

    test('ClientException and TimeoutException are network', () {
      expect(
        classifyActionFailureKind(ClientException('offline')),
        AnalyticsErrorKind.network,
      );
      expect(
        classifyActionFailureKind(TimeoutException('slow')),
        AnalyticsErrorKind.network,
      );
    });

    test('StorageException 403 is auth, 503 is server', () {
      expect(
        classifyActionFailureKind(
          const StorageException('policy denied', statusCode: '403'),
        ),
        AnalyticsErrorKind.auth,
      );
      expect(
        classifyActionFailureKind(
          const StorageException('service unavailable', statusCode: '503'),
        ),
        AnalyticsErrorKind.server,
      );
    });

    test('local file, sqlite, Drift, and framework failures are named', () {
      final sqliteError = _sqliteException();

      expect(
        classifyActionFailureKind(const FileSystemException('missing')),
        AnalyticsErrorKind.file,
      );
      expect(classifyActionFailureKind(sqliteError), AnalyticsErrorKind.db);
      expect(
        classifyActionFailureKind(
          DriftWrappedException(message: 'bad statement', cause: sqliteError),
        ),
        AnalyticsErrorKind.db,
      );
      expect(
        classifyActionFailureKind(FlutterError('layout failed')),
        AnalyticsErrorKind.app,
      );
      expect(
        classifyActionFailureKind(StateError('bad state')),
        AnalyticsErrorKind.app,
      );
      expect(classifyActionFailureKind(NotInitializedError()),
          AnalyticsErrorKind.app);
    });
  });

  test('reportActionFailed captures sanitized properties and error_kind', () {
    final events = <Map<String, Object?>>[];
    final analytics = _RecordingAnalytics(events);

    analytics.reportActionFailed(
      screen: 'create_trip',
      action: 'create_trip',
      error: const PostgrestException(
        message: 'Could not find the function public.create_trip',
        code: 'PGRST202',
      ),
    );

    expect(events, [
      {
        'event': VamoEvent.actionFailed,
        'properties': {
          'screen': 'create_trip',
          'action': 'create_trip',
          'severity': 'failure',
          'error_kind': 'server',
          'error_code': 'postgrest_function_not_found',
        },
      },
    ]);
  });

  test('reportAndLog reports sanitized degraded failures', () {
    final events = <Map<String, Object?>>[];

    reportAndLog(
      const FileSystemException('path contains /private/user.jpg'),
      StackTrace.current,
      screen: 'trip_home',
      action: 'set_trip_background',
      severity: ActionFailureSeverity.degraded,
      analytics: _RecordingAnalytics(events),
    );

    expect(events, [
      {
        'event': VamoEvent.actionFailed,
        'properties': {
          'screen': 'trip_home',
          'action': 'set_trip_background',
          'severity': 'degraded',
          'error_kind': 'file',
          'error_code': 'file_error',
        },
      },
    ]);
  });

  group('AnalyticsCaptureAction', () {
    test('reports capture lifecycle events', () {
      final events = <Map<String, Object?>>[];
      final analytics = _RecordingAnalytics(events);

      analytics.reportCaptureActionStarted(
        screen: 'trip_home',
        action: 'set_trip_background',
        sheetMounted: false,
      );
      analytics.reportCaptureActionAbandoned(
        screen: 'trip_home',
        action: 'set_trip_background',
        reason: 'unmounted_after_pick',
      );
      analytics.reportCaptureActionCompleted(
        screen: 'trip_home',
        action: 'set_trip_background',
      );

      expect(events, [
        {
          'event': VamoEvent.captureActionStarted,
          'properties': {
            'screen': 'trip_home',
            'action': 'set_trip_background',
            'sheet_mounted': false,
          },
        },
        {
          'event': VamoEvent.captureActionAbandoned,
          'properties': {
            'screen': 'trip_home',
            'action': 'set_trip_background',
            'reason': 'unmounted_after_pick',
          },
        },
        {
          'event': VamoEvent.captureActionCompleted,
          'properties': {
            'screen': 'trip_home',
            'action': 'set_trip_background',
          },
        },
      ]);
    });

    test('cancelled abandon carries reason', () {
      final events = <Map<String, Object?>>[];
      final analytics = _RecordingAnalytics(events);

      analytics.reportCaptureActionAbandoned(
        screen: 'trip_home',
        action: 'add_capture_photo',
        reason: 'cancelled',
      );

      expect(events.single['properties'], {
        'screen': 'trip_home',
        'action': 'add_capture_photo',
        'reason': 'cancelled',
      });
    });
  });
}

Object _sqliteException() {
  final database = sqlite3.openInMemory();
  try {
    database.select('select * from missing_table');
    throw StateError('sqlite query unexpectedly succeeded');
  } catch (error) {
    return error;
  } finally {
    database.dispose();
  }
}

class _RecordingAnalytics implements Analytics {
  _RecordingAnalytics(this.events);

  final List<Map<String, Object?>> events;

  @override
  void capture(VamoEvent event, {Map<String, Object?> properties = const {}}) {
    events.add({'event': event, 'properties': properties});
  }

  @override
  Future<void> identify(String userId) async {}

  @override
  Future<void> reset() async {}
}

class NotInitializedError implements Exception {}

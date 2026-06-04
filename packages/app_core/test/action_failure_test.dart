import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' show ClientException;
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
        'PGRST202',
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
          const AuthException('JWT expired', statusCode: '401', code: 'invalid_jwt'),
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

    test('AuthException is auth unless retryable fetch', () {
      expect(
        classifyActionFailureKind(const AuthException('bad token', code: '401')),
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
  });

  test('reportActionFailed captures sanitized properties', () {
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
          'kind': 'server',
          'code': 'PGRST202',
        },
      },
    ]);
  });
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

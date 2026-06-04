import 'package:app_core/src/fx/fx_rates_client.dart';
import 'package:app_core/src/fx/fx_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late FxRatesClient client;

  setUp(() {
    client = FxRatesClient(
      httpClient: MockClient((_) async => http.Response('error', 500)),
    );
  });

  test('parsePayloadForTest reads rates and base', () {
    final snapshot = client.parsePayloadForTest({
      'success': true,
      'base': 'EUR',
      'rates': {'USD': 1.08, 'GBP': 0.86},
      'fetched_at': '2026-06-01T12:00:00Z',
    });
    expect(snapshot.baseCurrency, 'EUR');
    expect(snapshot.unitsPerOneBase['USD'], 1.08);
    expect(snapshot.isStale, isFalse);
  });

  test('parsePayloadForTest throws on success:false', () {
    expect(
      () => client.parsePayloadForTest({
        'success': false,
        'error': {'info': 'Invalid access key'},
      }),
      throwsA(
        isA<FxRatesException>().having(
          (e) => e.message,
          'message',
          contains('Invalid access key'),
        ),
      ),
    );
  });

  test('fetchForBase returns stale cache when network fails', () async {
    client.seedPivotCacheForTest(
      FxRatesSnapshot(
        baseCurrency: 'EUR',
        unitsPerOneBase: const {'EUR': 1.0, 'USD': 1.1},
        fetchedAt: DateTime.utc(2026, 1, 1),
      ),
    );

    final result = await client.fetchForBase('EUR');
    expect(result.isStale, isTrue);
    expect(result.rateExpenseToBase('USD'), closeTo(1 / 1.1, 1e-9));
  });

  test('fetchForBase returns stale cache on ClientException', () async {
    client = FxRatesClient(
      httpClient: MockClient((_) async => throw http.ClientException('offline')),
    );
    client.seedPivotCacheForTest(
      FxRatesSnapshot(
        baseCurrency: 'EUR',
        unitsPerOneBase: const {'EUR': 1.0, 'USD': 1.1},
        fetchedAt: DateTime.utc(2026, 1, 1),
      ),
    );

    final result = await client.fetchForBase('EUR');
    expect(result.isStale, isTrue);
    expect(result.rateExpenseToBase('USD'), closeTo(1 / 1.1, 1e-9));
  });
}

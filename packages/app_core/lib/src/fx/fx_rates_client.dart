import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../env/env.dart';
import '../analytics/action_failure.dart';
import 'fx_rates_persistence.dart';
import 'fx_snapshot.dart';

/// Fetches pivot rates (EUR) from the edge function or exchangerate.host, rebases
/// to the trip currency, and falls back to stale cache when offline.
class FxRatesClient {
  FxRatesClient({http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  final http.Client _http;

  FxRatesSnapshot? _pivotSnapshot;
  bool _persistedLoaded = false;

  static const _freshTtl = Duration(hours: 12);

  Future<FxRatesSnapshot> fetchForBase(String baseCurrency) async {
    final tripBase = baseCurrency.toUpperCase();
    await _ensurePersistedLoaded();

    final pivot = _pivotSnapshot;
    if (pivot != null &&
        !pivot.isStale &&
        DateTime.now().toUtc().difference(pivot.fetchedAt) < _freshTtl) {
      return rebaseFxSnapshot(pivot, tripBase: tripBase);
    }

    try {
      final freshPivot = await _fetchPivotFromNetwork();
      _pivotSnapshot = freshPivot;
      await FxRatesPersistence.save(freshPivot);
      return rebaseFxSnapshot(freshPivot, tripBase: tripBase);
    } on FxRatesException {
      return _staleForTripBase(tripBase);
    } on http.ClientException {
      return _staleForTripBase(tripBase);
    } on TimeoutException {
      return _staleForTripBase(tripBase);
    } on FormatException {
      return _staleForTripBase(tripBase);
    } catch (error, stackTrace) {
      reportAndLog(
        error,
        stackTrace,
        screen: 'fx',
        action: 'fetch_rates',
        severity: ActionFailureSeverity.degraded,
      );
      return _staleForTripBase(tripBase);
    }
  }

  Future<void> _ensurePersistedLoaded() async {
    if (_persistedLoaded) return;
    _persistedLoaded = true;
    _pivotSnapshot ??= await FxRatesPersistence.load();
  }

  Future<FxRatesSnapshot> _staleForTripBase(String tripBase) {
    final pivot = _pivotSnapshot;
    if (pivot != null) {
      return Future.value(
        rebaseFxSnapshot(pivot, tripBase: tripBase, isStale: true),
      );
    }
    throw FxRatesException(
      'FX rates unavailable offline. Connect once while adding a foreign '
      'expense, or use the trip base currency.',
    );
  }

  Future<FxRatesSnapshot> _fetchPivotFromNetwork() async {
    final functionUrl = Env.fxRatesFunctionUrl.trim();
    if (functionUrl.isNotEmpty) {
      return _fetchPivotFromFunction(functionUrl);
    }
    return _fetchPivotFromExchangerateHost();
  }

  Future<FxRatesSnapshot> _fetchPivotFromFunction(String url) async {
    final query = <String, String>{
      'base': fxRatesPivotCurrency,
      if (Env.exchangerateAccessKey.isNotEmpty)
        'access_key': Env.exchangerateAccessKey,
    };
    final uri = Uri.parse(url).replace(queryParameters: query);
    final response = await _http.get(uri);
    if (response.statusCode != 200) {
      throw FxRatesException(
        'FX function returned ${response.statusCode}',
      );
    }
    return _parsePayload(
      jsonDecode(response.body) as Map<String, dynamic>,
      expectedBase: fxRatesPivotCurrency,
    );
  }

  Future<FxRatesSnapshot> _fetchPivotFromExchangerateHost() async {
    final key = Env.exchangerateAccessKey.trim();
    if (key.isEmpty) {
      throw FxRatesException(
        'Missing EXCHANGERATE_ACCESS_KEY. Get a free key at exchangerate.host '
        'or set FX_RATES_FUNCTION_URL to the deployed fx-rates edge function.',
      );
    }

    final uri = Uri.https(
      'api.exchangerate.host',
      '/latest',
      {
        'access_key': key,
        'base': fxRatesPivotCurrency,
      },
    );
    final response = await _http.get(uri);
    if (response.statusCode != 200) {
      throw FxRatesException(
        'exchangerate.host returned ${response.statusCode}',
      );
    }
    return _parsePayload(
      jsonDecode(response.body) as Map<String, dynamic>,
      expectedBase: fxRatesPivotCurrency,
    );
  }

  FxRatesSnapshot _parsePayload(
    Map<String, dynamic> body, {
    required String expectedBase,
  }) {
    _throwIfApiError(body);

    final base = (body['base'] as String? ?? expectedBase).toUpperCase();
    final ratesRaw = body['rates'] as Map<String, dynamic>?;
    if (ratesRaw == null || ratesRaw.isEmpty) {
      throw FxRatesException('FX response missing rates');
    }

    final units = <String, double>{base: 1.0};
    for (final entry in ratesRaw.entries) {
      final code = entry.key.toString().toUpperCase();
      final value = entry.value;
      if (value is num && value > 0) {
        units[code] = value.toDouble();
      }
    }

    final fetchedAt = body['fetched_at'] != null
        ? DateTime.tryParse(body['fetched_at'] as String) ?? DateTime.now()
        : DateTime.now();

    return FxRatesSnapshot(
      baseCurrency: base,
      unitsPerOneBase: units,
      fetchedAt: fetchedAt.toUtc(),
    );
  }

  void _throwIfApiError(Map<String, dynamic> body) {
    if (body['success'] == false) {
      final err = body['error'];
      final message = err is Map
          ? (err['info'] ?? err['type'] ?? err).toString()
          : err?.toString() ?? 'upstream error';
      throw FxRatesException('exchangerate.host: $message');
    }
    if (body['error'] != null && body['rates'] == null) {
      throw FxRatesException('FX upstream: ${body['error']}');
    }
  }

  void clearCache() {
    _pivotSnapshot = null;
    _persistedLoaded = false;
  }

  @visibleForTesting
  void seedPivotCacheForTest(FxRatesSnapshot pivot) {
    _pivotSnapshot = pivot;
    _persistedLoaded = true;
  }

  @visibleForTesting
  FxRatesSnapshot parsePayloadForTest(Map<String, dynamic> body) {
    return _parsePayload(body, expectedBase: fxRatesPivotCurrency);
  }
}

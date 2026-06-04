import 'fx_math.dart';

/// Pivot used for upstream fetches (exchangerate.host default; avoids per-base API tiers).
const fxRatesPivotCurrency = 'EUR';

/// Daily FX rates for converting expenses into a trip's base currency.
class FxRatesSnapshot {
  const FxRatesSnapshot({
    required this.baseCurrency,
    required this.unitsPerOneBase,
    required this.fetchedAt,
    this.isStale = false,
  });

  final String baseCurrency;

  /// For each currency code, how many units of that currency equal 1 [baseCurrency].
  final Map<String, double> unitsPerOneBase;

  final DateTime fetchedAt;

  /// True when returned from cache after a failed live fetch (rate may be outdated).
  final bool isStale;

  double rateExpenseToBase(String expenseCurrency) => fxRateExpenseToBase(
        expenseCurrency: expenseCurrency,
        baseCurrency: baseCurrency,
        unitsPerOneBase: unitsPerOneBase,
      );

  int toBaseCents({
    required int amountCents,
    required String expenseCurrency,
  }) {
    final rate = rateExpenseToBase(expenseCurrency);
    return convertExpenseCentsToBase(amountCents: amountCents, fxRate: rate);
  }

  Map<String, dynamic> toJson() => {
        'base_currency': baseCurrency,
        'units_per_one_base': unitsPerOneBase,
        'fetched_at': fetchedAt.toIso8601String(),
      };

  static FxRatesSnapshot fromJson(Map<String, dynamic> json) {
    final ratesRaw = json['units_per_one_base'] as Map<String, dynamic>? ??
        json['rates'] as Map<String, dynamic>?;
    final units = <String, double>{};
    if (ratesRaw != null) {
      for (final entry in ratesRaw.entries) {
        final value = entry.value;
        if (value is num && value > 0) {
          units[entry.key.toString().toUpperCase()] = value.toDouble();
        }
      }
    }
    final base = (json['base_currency'] as String? ?? fxRatesPivotCurrency)
        .toUpperCase();
    units.putIfAbsent(base, () => 1.0);

    return FxRatesSnapshot(
      baseCurrency: base,
      unitsPerOneBase: units,
      fetchedAt: DateTime.parse(json['fetched_at'] as String).toUtc(),
      isStale: json['is_stale'] as bool? ?? true,
    );
  }
}

class FxRatesException implements Exception {
  FxRatesException(this.message);
  final String message;
  @override
  String toString() => 'FxRatesException: $message';
}

/// Rebases [pivot] rates (units per 1 pivot base) to [tripBase] units per 1 trip base.
FxRatesSnapshot rebaseFxSnapshot(
  FxRatesSnapshot pivot, {
  required String tripBase,
  bool isStale = false,
}) {
  final target = tripBase.toUpperCase();
  if (pivot.baseCurrency == target) {
    return FxRatesSnapshot(
      baseCurrency: target,
      unitsPerOneBase: pivot.unitsPerOneBase,
      fetchedAt: pivot.fetchedAt,
      isStale: isStale || pivot.isStale,
    );
  }

  final divisor = pivot.unitsPerOneBase[target];
  if (divisor == null || divisor <= 0) {
    throw FxRatesException('No FX rate for trip base $target');
  }

  final rebased = <String, double>{target: 1.0};
  for (final entry in pivot.unitsPerOneBase.entries) {
    rebased[entry.key] = entry.value / divisor;
  }

  return FxRatesSnapshot(
    baseCurrency: target,
    unitsPerOneBase: rebased,
    fetchedAt: pivot.fetchedAt,
    isStale: isStale || pivot.isStale,
  );
}

/// Pure FX helpers — rates are "units of [currency] per 1 unit of trip base"
/// (exchangerate.host style: base EUR → USD 1.08 means 1 EUR = 1.08 USD).

/// Multiplier from [expenseCurrency] cents to trip [baseCurrency] cents.
double fxRateExpenseToBase({
  required String expenseCurrency,
  required String baseCurrency,
  required Map<String, double> unitsPerOneBase,
}) {
  if (expenseCurrency == baseCurrency) return 1.0;
  final units = unitsPerOneBase[expenseCurrency];
  if (units == null || units <= 0) {
    throw ArgumentError('No FX rate for $expenseCurrency (base $baseCurrency)');
  }
  return 1.0 / units;
}

/// `base_cents = round(amount_cents * fx_rate)` per Wave 1 spec.
int convertExpenseCentsToBase({
  required int amountCents,
  required double fxRate,
}) {
  return (amountCents * fxRate).round();
}

/// Receipt-printed trip-base total ÷ expense amount (additive S50 path).
double fxRateFromReceiptTotals({
  required int amountCents,
  required int receiptBaseCents,
}) {
  if (amountCents <= 0) {
    throw ArgumentError.value(amountCents, 'amountCents', 'must be positive');
  }
  if (receiptBaseCents <= 0) {
    throw ArgumentError.value(
      receiptBaseCents,
      'receiptBaseCents',
      'must be positive',
    );
  }
  return receiptBaseCents / amountCents;
}

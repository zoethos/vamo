import 'money_format.dart';

/// Primary amount in trip base; secondary line when spent in another currency.
/// Amounts are bidi-wrapped for RTL list tiles (T13.3).
String formatExpenseTrailing({
  required int baseCents,
  required String tripBaseCurrency,
  required int amountCents,
  required String expenseCurrency,
  String? locale,
  bool bidi = true,
}) {
  String wrap(String value) => bidi ? wrapMoneyForBidi(value) : value;

  final base = formatMoneyFromCents(
    baseCents,
    tripBaseCurrency,
    locale: locale,
  );
  if (expenseCurrency == tripBaseCurrency) return wrap(base);
  final spent = formatMoneyFromCents(
    amountCents,
    expenseCurrency,
    locale: locale,
  );
  return '${wrap(base)}\n(${wrap(spent)})';
}

/// Builds a bidi-safe expense row subtitle: payer · date with isolated amount context.
String formatExpenseSubtitle({
  required String payer,
  required String when,
  required int baseCents,
  required String tripBaseCurrency,
}) {
  return '$payer · $when · ${formatMoneyFromCentsBidi(baseCents, tripBaseCurrency)}';
}

import 'money_format.dart';

/// Primary amount in trip base; secondary line when spent in another currency.
String formatExpenseTrailing({
  required int baseCents,
  required String tripBaseCurrency,
  required int amountCents,
  required String expenseCurrency,
}) {
  final base = formatMoneyFromCents(baseCents, tripBaseCurrency);
  if (expenseCurrency == tripBaseCurrency) return base;
  final spent = formatMoneyFromCents(amountCents, expenseCurrency);
  return '$base\n($spent)';
}

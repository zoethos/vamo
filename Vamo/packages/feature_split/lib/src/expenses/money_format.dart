import 'package:intl/intl.dart';

/// Parses a user-entered decimal amount (e.g. "30" or "30.50") to integer cents.
int? parseAmountToCents(String input) {
  final normalized = input.trim().replaceAll(',', '.');
  if (normalized.isEmpty) return null;
  final value = double.tryParse(normalized);
  if (value == null || value <= 0) return null;
  return (value * 100).round();
}

String formatMoneyFromCents(int cents, String currencyCode) {
  final amount = cents / 100;
  return NumberFormat.simpleCurrency(name: currencyCode).format(amount);
}

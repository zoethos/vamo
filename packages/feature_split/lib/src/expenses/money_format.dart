import 'package:intl/intl.dart';

/// Unicode directional isolates for embedding LTR money in RTL sentences.
const ltrIsolateStart = '\u2066';
const ltrIsolateEnd = '\u2069';

/// Parses a user-entered decimal amount (e.g. "30" or "30.50") to integer cents.
int? parseAmountToCents(String input) {
  final normalized = input.trim().replaceAll(',', '.');
  if (normalized.isEmpty) return null;
  final value = double.tryParse(normalized);
  if (value == null || value <= 0) return null;
  return (value * 100).round();
}

/// Locale-aware currency formatting. Uses Western digits for amounts (T13 plan).
String formatMoneyFromCents(
  int cents,
  String currencyCode, {
  String? locale,
}) {
  final amount = cents / 100;
  final formatter = locale == null
      ? NumberFormat.simpleCurrency(name: currencyCode)
      : NumberFormat.simpleCurrency(locale: locale, name: currencyCode);
  return formatter.format(amount);
}

/// Wraps [formatMoneyFromCents] in LTR isolates for bidi-safe embedding (T13.3).
String formatMoneyFromCentsBidi(
  int cents,
  String currencyCode, {
  String? locale,
}) {
  final formatted = formatMoneyFromCents(
    cents,
    currencyCode,
    locale: locale,
  );
  return '$ltrIsolateStart$formatted$ltrIsolateEnd';
}

/// Embeds an already-formatted money string in LTR isolates.
String wrapMoneyForBidi(String formattedAmount) {
  return '$ltrIsolateStart$formattedAmount$ltrIsolateEnd';
}

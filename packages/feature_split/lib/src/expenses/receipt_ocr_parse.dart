import 'package:app_core/app_core.dart';

import 'receipt_ocr_models.dart';

/// Pure parser — unit-tested with receipt-shaped fixtures (no ML Kit).
ReceiptParseResult receiptParse(String rawText) {
  final lines = rawText
      .split(RegExp(r'[\r\n]+'))
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();

  if (lines.isEmpty) return const ReceiptParseResult();

  final currency = _detectCurrency(rawText, lines);
  final amountCents = _detectAmountCents(lines, currency);
  final merchant = _detectMerchant(lines);
  final address = _detectAddress(lines);
  final date = _detectDate(rawText);

  return ReceiptParseResult(
    amountCents: amountCents,
    currency: currency,
    merchant: merchant,
    address: address,
    date: date,
  );
}

final _totalKeywords = RegExp(
  r'\b(TOTAL|TOTALE|SUMME|GESAMT|IMPORTE|AMOUNT|SUBTOTAL|'
  r'TVA|IVA|MWST|GRAND\s*TOTAL|TO\s*PAY|DA\s*PAGARE|'
  r'ZU\s*ZAHLEN|BETRAG)\b',
  caseSensitive: false,
);

final _vatIdPattern = RegExp(
  r'\b(?:P\.?\s*IVA|IVA|VAT|UID|USt-IdNr|Partita\s*IVA|'
  r'CIF|NIF|Steuernr)[\s.:]*[A-Z0-9./-]+\b',
  caseSensitive: false,
);

final _addressHints = RegExp(
  r'\b(via|viale|piazza|str\.|rue|avenue|platz|corso|via\s|calle)\b|'
  r'straße|strasse|str\.',
  caseSensitive: false,
);

final _streetAddressPattern = RegExp(
  r'^\d{1,4}\s+[A-Za-zÀ-ÿ]',
  caseSensitive: false,
);

final _streetSuffix = RegExp(
  r'\b(street|st\.?|road|rd\.?|lane|ln\.?|avenue|ave\.?|'
  r'boulevard|blvd\.?|drive|dr\.?|way|high\s+street)\b',
  caseSensitive: false,
);

final _postalCityPattern = RegExp(
  r'\b\d{4,5}(?:\s*[-\s]\s*\d{4})?\b.*[A-Za-zÀ-ÿ]{2,}|'
  r'[A-Za-zÀ-ÿ]{2,}.*\b\d{4,5}\b|'
  r'\b[A-Z]{1,2}\d[A-Z\d]?\s*\d[A-Z]{2}\b',
  caseSensitive: false,
);

int? _detectAmountCents(List<String> lines, String? currencyHint) {
  final amountsNearTotal = <int>[];
  final allAmounts = <int>[];

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final tokens = _moneyTokensInLine(line);
    for (final cents in tokens) {
      allAmounts.add(cents);
      if (_totalKeywords.hasMatch(line)) {
        amountsNearTotal.add(cents);
      }
      if (i > 0 && _totalKeywords.hasMatch(lines[i - 1])) {
        amountsNearTotal.add(cents);
      }
      if (i + 1 < lines.length && _totalKeywords.hasMatch(lines[i + 1])) {
        amountsNearTotal.add(cents);
      }
    }
  }

  if (amountsNearTotal.isNotEmpty) {
    return amountsNearTotal.reduce((a, b) => a > b ? a : b);
  }
  if (allAmounts.isEmpty) return null;

  // Ignore tiny amounts (tax lines) when a larger total exists.
  allAmounts.sort();
  final max = allAmounts.last;
  if (max >= 500 && allAmounts.length > 1) {
    final large = allAmounts.where((c) => c >= max ~/ 4).toList();
    if (large.isNotEmpty) return large.last;
  }
  return max;
}

List<int> _moneyTokensInLine(String line) {
  final results = <int>[];
  final pattern = RegExp(
    r'(?:€|EUR|\$|USD|£|GBP|CHF)\s*([\d][\d.,\s]*)|'
    r'([\d][\d.,\s]*)\s*(?:€|EUR|\$|USD|£|GBP|CHF)',
    caseSensitive: false,
  );
  for (final m in pattern.allMatches(line)) {
    final raw = (m.group(1) ?? m.group(2))?.replaceAll(' ', '');
    final cents = raw == null ? null : _parseMoneyToCents(raw);
    if (cents != null && cents > 0) results.add(cents);
  }

  // Bare amounts on total-like lines or trailing decimals.
  if (results.isEmpty || _totalKeywords.hasMatch(line)) {
    for (final m
        in RegExp(r'([\d]{1,3}(?:[.,]\d{3})*[.,]\d{2})').allMatches(line)) {
      final cents = _parseMoneyToCents(m.group(1)!);
      if (cents != null && cents > 0) results.add(cents);
    }
  }
  return results;
}

int? _parseMoneyToCents(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return null;

  // European: 1.234,56
  if (RegExp(r'^\d{1,3}(\.\d{3})+,\d{2}$').hasMatch(s)) {
    s = s.replaceAll('.', '').replaceAll(',', '.');
  } else if (s.contains(',') && s.contains('.')) {
    if (s.lastIndexOf(',') > s.lastIndexOf('.')) {
      s = s.replaceAll('.', '').replaceAll(',', '.');
    } else {
      s = s.replaceAll(',', '');
    }
  } else if (s.contains(',') && !s.contains('.')) {
    final parts = s.split(',');
    if (parts.length == 2 && parts[1].length == 2) {
      s = '${parts[0]}.${parts[1]}';
    } else {
      s = s.replaceAll(',', '');
    }
  }

  final value = double.tryParse(s);
  if (value == null || value <= 0 || value > 999999.99) return null;
  return (value * 100).round();
}

String? _detectCurrency(String raw, List<String> lines) {
  if (raw.contains('€') ||
      RegExp(r'\bEUR\b', caseSensitive: false).hasMatch(raw)) {
    return 'EUR';
  }
  if (raw.contains(r'$') ||
      RegExp(r'\bUSD\b', caseSensitive: false).hasMatch(raw)) {
    return 'USD';
  }
  if (raw.contains('£') ||
      RegExp(r'\bGBP\b', caseSensitive: false).hasMatch(raw)) {
    return 'GBP';
  }
  if (RegExp(r'\bCHF\b', caseSensitive: false).hasMatch(raw)) {
    return 'CHF';
  }
  for (final line in lines.reversed) {
    if (line.contains('€')) return 'EUR';
    if (line.contains(r'$')) return 'USD';
    if (line.contains('£')) return 'GBP';
    if (RegExp(r'\bCHF\b').hasMatch(line)) return 'CHF';
  }
  return null;
}

String? _detectMerchant(List<String> lines) {
  final candidates = <String>[];
  final scanLimit = lines.length < 8 ? lines.length : 8;

  for (var i = 0; i < scanLimit; i++) {
    final line = lines[i];
    if (_isNoiseLine(line)) continue;
    final cleaned = _cleanMerchantLine(line);
    if (cleaned == null || cleaned.length < 3) continue;
    candidates.add(cleaned);
    if (candidates.length >= 2) break;
  }

  if (candidates.isEmpty) return null;
  return candidates.take(2).join(' · ');
}

bool _isNoiseLine(String line) {
  if (_totalKeywords.hasMatch(line)) return true;
  if (RegExp(r'^\d+$').hasMatch(line)) return true;
  if (RegExp(r'^[\d\s./:-]+$').hasMatch(line)) return true;
  if (_moneyTokensInLine(line).isNotEmpty && line.length < 24) return true;
  if (_vatIdPattern.hasMatch(line)) return true;
  if (_streetAddressPattern.hasMatch(line) || _streetSuffix.hasMatch(line)) {
    return true;
  }
  if (_postalCityPattern.hasMatch(line)) return true;
  if (_addressHints.hasMatch(line) && line.length > 28) return true;
  if (_isAddressLine(line)) return true;
  final letters = RegExp(r'[A-Za-zÀ-ÿ]').allMatches(line).length;
  if (letters < line.length ~/ 4) return true;
  return false;
}

String? _detectAddress(List<String> lines) {
  final parts = <String>[];
  final scanLimit = lines.length < 12 ? lines.length : 12;

  for (var i = 0; i < scanLimit; i++) {
    final line = lines[i];
    if (_isAddressLine(line)) {
      parts.add(line.trim());
      if (parts.length >= 3) break;
    }
  }

  if (parts.isEmpty) return null;
  return parts.join(', ');
}

bool _isAddressLine(String line) {
  if (_totalKeywords.hasMatch(line)) return false;
  if (_vatIdPattern.hasMatch(line)) return false;
  if (_streetAddressPattern.hasMatch(line) || _streetSuffix.hasMatch(line)) {
    return true;
  }
  if (_addressHints.hasMatch(line)) return true;
  if (_postalCityPattern.hasMatch(line)) return true;
  return false;
}

String? _cleanMerchantLine(String line) {
  var s = line;
  s = s.replaceAll(_vatIdPattern, '').trim();
  s = s.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
  if (s.length > 48) s = s.substring(0, 48).trim();
  return s.isEmpty ? null : s;
}

DateTime? _detectDate(String raw) {
  final patterns = [
    RegExp(r'(\d{2})[./-](\d{2})[./-](\d{4})'),
    RegExp(r'(\d{4})[./-](\d{2})[./-](\d{2})'),
  ];
  for (final p in patterns) {
    final m = p.firstMatch(raw);
    if (m == null) continue;
    try {
      if (m.group(1)!.length == 4) {
        return DateTime.utc(
          int.parse(m.group(1)!),
          int.parse(m.group(2)!),
          int.parse(m.group(3)!),
        );
      }
      return DateTime.utc(
        int.parse(m.group(3)!),
        int.parse(m.group(2)!),
        int.parse(m.group(1)!),
      );
    } catch (error, stackTrace) {
      reportAndLog(
        error,
        stackTrace,
        screen: 'receipt',
        action: 'detect_receipt_date',
        severity: ActionFailureSeverity.degraded,
      );
      continue;
    }
  }
  return null;
}

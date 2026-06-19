/// Parsed fields from on-device receipt OCR (user always confirms before save).
class ReceiptParseResult {
  const ReceiptParseResult({
    this.amountCents,
    this.currency,
    this.merchant,
    this.address,
    this.date,
    this.printedBaseCents,
    this.printedBaseCurrency,
  });

  /// Total in minor units (e.g. cents).
  final int? amountCents;

  /// ISO 4217 code.
  final String? currency;

  /// Merchant / place name candidate → title + place_label.
  final String? merchant;

  /// Street / city lines from the receipt header.
  final String? address;

  final DateTime? date;

  /// Optional trip-base total printed on the receipt (S50 receipt-rate path).
  final int? printedBaseCents;

  /// ISO code for [printedBaseCents] when detected.
  final String? printedBaseCurrency;

  bool get hasAnySuggestion =>
      amountCents != null ||
      (currency != null && currency!.isNotEmpty) ||
      (merchant != null && merchant!.isNotEmpty) ||
      date != null;

  bool get hasReceiptFxHint =>
      amountCents != null &&
      amountCents! > 0 &&
      printedBaseCents != null &&
      printedBaseCents! > 0 &&
      printedBaseCurrency != null &&
      currency != null &&
      currency!.toUpperCase() != printedBaseCurrency!.toUpperCase();
}

/// Which add-expense fields were pre-filled from OCR (for analytics).
enum OcrSuggestionField { amount, currency, title, placeLabel }

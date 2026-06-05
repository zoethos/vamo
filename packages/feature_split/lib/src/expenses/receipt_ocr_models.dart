/// Parsed fields from on-device receipt OCR (user always confirms before save).
class ReceiptParseResult {
  const ReceiptParseResult({
    this.amountCents,
    this.currency,
    this.merchant,
    this.address,
    this.date,
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

  bool get hasAnySuggestion =>
      amountCents != null ||
      (currency != null && currency!.isNotEmpty) ||
      (merchant != null && merchant!.isNotEmpty) ||
      date != null;
}

/// Which add-expense fields were pre-filled from OCR (for analytics).
enum OcrSuggestionField { amount, currency, title, placeLabel }

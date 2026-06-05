import 'receipt_ocr_models.dart';

/// Supported expense currencies on the add-expense form.
const kExpenseFormCurrencies = ['EUR', 'USD', 'GBP', 'CHF'];

/// Form fields pre-filled from [receiptParse] / on-device OCR.
class OcrFormPrefillSnapshot {
  const OcrFormPrefillSnapshot({
    this.amountText,
    this.currency,
    this.description,
    this.placeLabel,
    this.suggestedFields = const {},
    this.ocrUsed = false,
  });

  final String? amountText;
  final String? currency;
  final String? description;
  final String? placeLabel;
  final Set<OcrSuggestionField> suggestedFields;
  final bool ocrUsed;
}

/// Pure mapping from parser output to add-expense form values (user confirms).
OcrFormPrefillSnapshot applyReceiptOcrPrefill({
  required ReceiptParseResult suggestion,
  List<String> supportedCurrencies = kExpenseFormCurrencies,
  bool currencyUserTouched = false,
  String currentDescription = '',
}) {
  if (!suggestion.hasAnySuggestion) {
    return const OcrFormPrefillSnapshot();
  }

  final suggested = <OcrSuggestionField>{};
  String? amountText;
  String? currency;
  String? description;
  String? placeLabel;

  if (suggestion.amountCents != null) {
    amountText = (suggestion.amountCents! / 100).toStringAsFixed(2);
    suggested.add(OcrSuggestionField.amount);
  }
  if (suggestion.currency != null &&
      supportedCurrencies.contains(suggestion.currency) &&
      !currencyUserTouched) {
    currency = suggestion.currency;
    suggested.add(OcrSuggestionField.currency);
  }
  if (suggestion.merchant != null && suggestion.merchant!.isNotEmpty) {
    if (currentDescription.trim().isEmpty) {
      description = suggestion.merchant;
      suggested.add(OcrSuggestionField.title);
    }
    placeLabel = suggestion.merchant;
    suggested.add(OcrSuggestionField.placeLabel);
  }

  return OcrFormPrefillSnapshot(
    amountText: amountText,
    currency: currency,
    description: description,
    placeLabel: placeLabel,
    suggestedFields: suggested,
    ocrUsed: suggested.isNotEmpty,
  );
}

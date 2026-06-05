import 'package:app_core/app_core.dart';
import 'package:feature_split/src/expenses/ocr_suggestion_chip.dart';
import 'package:feature_split/src/expenses/receipt_ocr_form_prefill.dart';
import 'package:feature_split/src/expenses/receipt_ocr_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('applyReceiptOcrPrefill maps parser output to form fields', () {
    const suggestion = ReceiptParseResult(
      amountCents: 2499,
      currency: 'EUR',
      merchant: 'Trattoria Da Mario',
    );

    final prefill = applyReceiptOcrPrefill(suggestion: suggestion);

    expect(prefill.ocrUsed, isTrue);
    expect(prefill.amountText, '24.99');
    expect(prefill.currency, 'EUR');
    expect(prefill.description, 'Trattoria Da Mario');
    expect(prefill.placeLabel, 'Trattoria Da Mario');
    expect(prefill.suggestedFields, {
      OcrSuggestionField.amount,
      OcrSuggestionField.currency,
      OcrSuggestionField.title,
      OcrSuggestionField.placeLabel,
    });
  });

  testWidgets('OCR pre-fill shows from-receipt chips on suggested fields', (
    tester,
  ) async {
    const suggestion = ReceiptParseResult(
      amountCents: 1295,
      currency: 'GBP',
      merchant: 'BISTRO LYON',
    );
    final prefill = applyReceiptOcrPrefill(suggestion: suggestion);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (prefill.suggestedFields.contains(OcrSuggestionField.currency))
                DropdownButton<String>(
                  value: prefill.currency,
                  items: kExpenseFormCurrencies
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (_) {},
                ),
              if (prefill.suggestedFields.contains(OcrSuggestionField.currency))
                const OcrSuggestionChip(),
              TextFormField(
                key: const Key('amount'),
                initialValue: prefill.amountText,
                decoration: const InputDecoration(labelText: 'Amount'),
              ),
              if (prefill.suggestedFields.contains(OcrSuggestionField.amount))
                const OcrSuggestionChip(),
              TextFormField(
                key: const Key('description'),
                initialValue: prefill.description,
                decoration: const InputDecoration(labelText: 'Description'),
              ),
              if (prefill.suggestedFields.contains(OcrSuggestionField.title))
                const OcrSuggestionChip(),
              if (prefill.placeLabel != null)
                Text(prefill.placeLabel!, key: const Key('place')),
              if (prefill.suggestedFields.contains(OcrSuggestionField.placeLabel))
                const OcrSuggestionChip(),
            ],
          ),
        ),
      ),
    );

    expect(find.text('from receipt'), findsNWidgets(4));
    expect(find.byKey(const Key('amount')), findsOneWidget);
    expect(
      tester.widget<TextFormField>(find.byKey(const Key('amount'))).initialValue,
      '12.95',
    );
    expect(find.text('BISTRO LYON'), findsNWidgets(2));
  });
}

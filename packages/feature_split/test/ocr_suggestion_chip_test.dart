import 'package:app_core/app_core.dart';
import 'package:feature_split/src/expenses/ocr_suggestion_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('OcrSuggestionChip uses goLime background and ink label', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: OcrSuggestionChip()),
      ),
    );

    expect(find.text('from receipt'), findsOneWidget);
    final chip = tester.widget<Chip>(find.byType(Chip));
    expect(chip.backgroundColor, AppColors.goLime.withValues(alpha: 0.35));
    final label = chip.label as Text;
    expect((label.style?.color), AppColors.ink);
  });
}

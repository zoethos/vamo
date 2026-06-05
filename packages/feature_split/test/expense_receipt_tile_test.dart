import 'dart:io';

import 'package:app_core/app_core.dart';
import 'package:feature_split/src/expenses/trip_expense_list_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late File receiptFile;

  setUp(() async {
    receiptFile = File(
      '${Directory.systemTemp.path}/vamo_receipt_test_${DateTime.now().microsecondsSinceEpoch}.png',
    );
    await receiptFile.writeAsBytes(const [
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
      0x00,
      0x00,
      0x00,
      0x0D,
      0x49,
      0x48,
      0x44,
      0x52,
      0x00,
      0x00,
      0x00,
      0x01,
      0x00,
      0x00,
      0x00,
      0x01,
      0x08,
      0x06,
      0x00,
      0x00,
      0x00,
      0x1F,
      0x15,
      0xC4,
      0x89,
      0x00,
      0x00,
      0x00,
      0x0A,
      0x49,
      0x44,
      0x41,
      0x54,
      0x78,
      0x9C,
      0x63,
      0x00,
      0x01,
      0x00,
      0x00,
      0x05,
      0x00,
      0x01,
      0x0D,
      0x0A,
      0x2D,
      0xB4,
      0x00,
      0x00,
      0x00,
      0x00,
      0x49,
      0x45,
      0x4E,
      0x44,
      0xAE,
      0x42,
      0x60,
      0x82,
    ]);
  });

  tearDown(() async {
    if (await receiptFile.exists()) {
      await receiptFile.delete();
    }
  });

  testWidgets('expense with receipt shows thumbnail indicator', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: TripExpenseListTile(
              description: 'Dinner',
              payer: 'Alex',
              spentAt: DateTime(2026, 6, 2),
              baseCents: 3000,
              amountCents: 3000,
              tripBaseCurrency: 'EUR',
              expenseCurrency: 'EUR',
              receiptThumbnailPath: receiptFile.path,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('expense_receipt_thumbnail')), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
  });
}

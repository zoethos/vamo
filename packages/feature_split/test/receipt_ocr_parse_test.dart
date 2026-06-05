import 'package:feature_split/src/expenses/receipt_ocr_parse.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('receiptParse — English', () {
    test('extracts total near TOTAL keyword', () {
      const raw = '''
COFFEE HOUSE LTD
123 Main St
Date: 02/06/2026
Latte        4.50
TOTAL        \$ 24.99
''';
      final r = receiptParse(raw);
      expect(r.amountCents, 2499);
      expect(r.currency, 'USD');
      expect(r.merchant, contains('COFFEE'));
    });
  });

  group('receiptParse — Italian', () {
    test('TOTALE with European decimal', () {
      const raw = '''
TRATTORIA DA MARIO
P.IVA IT12345678901
Via Roma 12, Roma
02/06/2026
Pasta        12,00
TOTALE EUR   45,80
''';
      final r = receiptParse(raw);
      expect(r.amountCents, 4580);
      expect(r.currency, 'EUR');
      expect(r.merchant, contains('TRATTORIA'));
    });

    test('DA PAGARE line', () {
      const raw = '''
BAR CENTRALE
DA PAGARE  18,50 €
''';
      final r = receiptParse(raw);
      expect(r.amountCents, 1850);
      expect(r.currency, 'EUR');
    });
  });

  group('receiptParse — German', () {
    test('SUMME with thousands separator', () {
      const raw = '''
CAFÉ BERLIN
SUMME        1.234,56 EUR
''';
      final r = receiptParse(raw);
      expect(r.amountCents, 123456);
      expect(r.currency, 'EUR');
    });
  });

  group('receiptParse — Spanish', () {
    test('IMPORTE total', () {
      const raw = '''
RESTAURANTE SOL
IMPORTE TOTAL  32,40 €
''';
      final r = receiptParse(raw);
      expect(r.amountCents, 3240);
      expect(r.currency, 'EUR');
    });
  });

  group('receiptParse — thermal quirks', () {
    test('prefers total line over item lines', () {
      const raw = '''
SHOP
item  3.00
item  5.00
TOTAL 12.34
''';
      expect(receiptParse(raw).amountCents, 1234);
    });

    test('CHF currency', () {
      const raw = '''
MIGROS
TOTAL CHF 15.90
''';
      final r = receiptParse(raw);
      expect(r.amountCents, 1590);
      expect(r.currency, 'CHF');
    });

    test('strips VAT id from merchant candidate', () {
      const raw = '''
BISTRO LYON
VAT GB123456789
12 High Street
TOTAL £ 9.99
''';
      final r = receiptParse(raw);
      expect(r.merchant, 'BISTRO LYON');
      expect(r.currency, 'GBP');
    });

    test('empty text returns empty result', () {
      final r = receiptParse('   \n  ');
      expect(r.hasAnySuggestion, isFalse);
    });

    test('extracts UK street address', () {
      const raw = '''
BISTRO LYON
12 High Street
London SW1A 1AA
TOTAL £ 9.99
''';
      final r = receiptParse(raw);
      expect(r.address, contains('12 High Street'));
      expect(r.merchant, 'BISTRO LYON');
    });
  });

  group('receiptParse — address lines', () {
    test('Italian via + city', () {
      const raw = '''
TRATTORIA DA MARIO
Via Roma 12, Roma
TOTALE EUR 45,80
''';
      final r = receiptParse(raw);
      expect(r.address, contains('Via Roma'));
    });

    test('German Straße', () {
      const raw = '''
CAFÉ BERLIN
Friedrichstraße 123
10117 Berlin
SUMME 12,00 EUR
''';
      final r = receiptParse(raw);
      expect(r.address, contains('Friedrichstraße'));
    });

    test('Spanish postal + city', () {
      const raw = '''
RESTAURANTE SOL
Calle Mayor 5
28013 Madrid
IMPORTE TOTAL 32,40 €
''';
      final r = receiptParse(raw);
      expect(r.address, contains('Calle Mayor'));
      expect(r.address, contains('28013'));
    });
  });

  group('receiptParse — dates', () {
    test('parses dd/mm/yyyy date', () {
      const raw = '''
CAFE
01/03/2026
TOTAL 10,00 €
''';
      final r = receiptParse(raw);
      expect(r.date, DateTime.utc(2026, 3, 1));
    });
  });
}

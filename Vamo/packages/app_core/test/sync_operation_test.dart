import 'package:app_core/app_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('expense insert payload round-trips', () {
    final payload = {
      'expense': {'id': 'e1', 'trip_id': 't1'},
      'shares': [
        {'id': 's1', 'expense_id': 'e1', 'share_cents': 1000},
      ],
    };
    final decoded = decodePayload(encodePayload(payload));
    expect(decoded['expense'], payload['expense']);
    expect((decoded['shares'] as List).length, 1);
  });
}

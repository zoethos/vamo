import 'package:app_core/app_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('expense insert payload round-trips with receipt fields', () {
    final payload = {
      'expense': {
        'id': 'e1',
        'trip_id': 't1',
        'payer_id': 'u1',
        'amount_cents': 3000,
        'currency': 'EUR',
        'base_cents': 3000,
        'fx_rate': 1.0,
        'description': 'Dinner',
        'spent_at': '2026-06-02T12:00:00.000Z',
        'created_by': 'u1',
        'receipt_path': 'u1/t1/receipts/e1.jpg',
        'captured_lat': 41.9028,
        'captured_lng': 12.4964,
        'captured_at': '2026-06-02T11:55:00.000Z',
        'place_label': 'Trattoria Da Mario',
      },
      'shares': [
        {
          'id': 's1',
          'expense_id': 'e1',
          'user_id': 'u1',
          'share_cents': 3000,
        },
      ],
    };
    final decoded = decodePayload(encodePayload(payload));
    final expense = decoded['expense'] as Map<String, dynamic>;
    final original = payload['expense'] as Map<String, dynamic>;
    expect(expense['receipt_path'], original['receipt_path']);
    expect(expense['captured_lat'], original['captured_lat']);
    expect(expense['captured_lng'], original['captured_lng']);
    expect(expense['captured_at'], original['captured_at']);
    expect(expense['place_label'], original['place_label']);
    expect((decoded['shares'] as List).length, 1);
  });

  test('expense update payload round-trips place_label patch', () {
    final payload = {
      'id': 'e1',
      'place_label': 'Caffè Centrale',
      'captured_at': '2026-06-02T11:55:00.000Z',
    };
    final decoded = decodePayload(encodePayload(payload));
    expect(decoded['id'], payload['id']);
    expect(decoded['place_label'], payload['place_label']);
    expect(decoded['captured_at'], payload['captured_at']);
  });

  test('place insert payload round-trips', () {
    final payload = {
      'id': 'pl1',
      'trip_id': 't1',
      'label': 'Trattoria Da Mario',
      'address': 'Via Roma 12, Roma',
      'lat': 41.9028,
      'lng': 12.4964,
      'source': 'both',
      'confidence': 0.9,
      'created_by': 'u1',
      'created_at': '2026-06-02T12:00:00.000Z',
    };
    final decoded = decodePayload(encodePayload(payload));
    expect(decoded['id'], payload['id']);
    expect(decoded['source'], 'both');
    expect(decoded['label'], payload['label']);
    expect(decoded['lat'], payload['lat']);
  });

  test('expense insert payload round-trips place_id', () {
    final payload = {
      'expense': {
        'id': 'e1',
        'trip_id': 't1',
        'payer_id': 'u1',
        'amount_cents': 3000,
        'currency': 'EUR',
        'base_cents': 3000,
        'fx_rate': 1.0,
        'description': 'Dinner',
        'spent_at': '2026-06-02T12:00:00.000Z',
        'created_by': 'u1',
        'place_id': 'pl1',
        'place_label': 'Trattoria Da Mario',
      },
      'shares': [],
    };
    final decoded = decodePayload(encodePayload(payload));
    final expense = decoded['expense'] as Map<String, dynamic>;
    expect(expense['place_id'], 'pl1');
  });

  test('receipt upload payload round-trips', () {
    final payload = {
      'expense_id': 'e1',
      'local_path': '/data/receipts/e1.jpg',
      'storage_path': 'u1/t1/receipts/e1.jpg',
    };
    final decoded = decodePayload(encodePayload(payload));
    expect(decoded['expense_id'], payload['expense_id']);
    expect(decoded['local_path'], payload['local_path']);
    expect(decoded['storage_path'], payload['storage_path']);
  });
}

import 'package:feature_split/src/poi/poi_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PoiSummary', () {
    test('parses normalized provider rows', () {
      final poi = PoiSummary.fromJson({
        'id': 'fsq-1',
        'name': 'Cafe Roma',
        'category': 'food',
        'lat': '48.137',
        'lng': 11.575,
        'source': 'foursquare',
        'providerPlaceId': 'fsq-1',
        'address': 'Marienplatz',
        'distanceM': 121.6,
        'description': 'Central square in Munich.',
        'website': 'https://example.com',
        'phone': '+491234',
        'hours': 'Open now',
        'rating': '8.7',
        'price': 2,
        'photoUrl': 'https://img.example/place.jpg',
      });

      expect(poi, isNotNull);
      expect(poi?.name, 'Cafe Roma');
      expect(poi?.category, PoiCategory.food);
      expect(poi?.lat, 48.137);
      expect(poi?.lng, 11.575);
      expect(poi?.distanceM, 122);
      expect(poi?.description, 'Central square in Munich.');
      expect(poi?.website, 'https://example.com');
      expect(poi?.phone, '+491234');
      expect(poi?.hours, 'Open now');
      expect(poi?.rating, 8.7);
      expect(poi?.price, 2);
      expect(poi?.photoUrl, 'https://img.example/place.jpg');
      expect(poi?.hasInfo, isTrue);
    });

    test('rejects rows missing trusted identity or coordinates', () {
      expect(
        PoiSummary.fromJson({
          'id': 'fsq-1',
          'name': 'Cafe Roma',
          'source': 'foursquare',
          'providerPlaceId': 'fsq-1',
        }),
        isNull,
      );
    });
  });

  group('PoiDiscoveryResult', () {
    test('parses available payload and drops malformed rows', () {
      final result = PoiDiscoveryResult.fromFunctionPayload({
        'available': true,
        'pois': [
          {
            'id': 'fsq-1',
            'name': 'Cafe Roma',
            'category': 'food',
            'lat': 48.137,
            'lng': 11.575,
            'source': 'foursquare',
            'providerPlaceId': 'fsq-1',
          },
          {'name': 'Broken'},
        ],
      });

      expect(result, isNotNull);
      expect(result?.gated, isFalse);
      expect(result?.pois, hasLength(1));
    });

    test('parses gated payload', () {
      final result = PoiDiscoveryResult.fromFunctionPayload({
        'gated': true,
        'reason': 'user_quota_exceeded',
      });

      expect(result, isNotNull);
      expect(result?.gated, isTrue);
      expect(result?.reason, 'user_quota_exceeded');
      expect(result?.pois, isEmpty);
    });

    test('preserves unavailable reasons', () {
      final result = PoiDiscoveryResult.fromFunctionPayload({
        'available': false,
        'reason': 'provider_auth',
      });

      expect(result, isNotNull);
      expect(result?.gated, isFalse);
      expect(result?.unavailable, isTrue);
      expect(result?.reason, 'provider_auth');
      expect(result?.pois, isEmpty);
    });
  });
}

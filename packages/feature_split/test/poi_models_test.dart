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
      });

      expect(poi, isNotNull);
      expect(poi?.name, 'Cafe Roma');
      expect(poi?.category, PoiCategory.food);
      expect(poi?.lat, 48.137);
      expect(poi?.lng, 11.575);
      expect(poi?.distanceM, 122);
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

    test('returns null for unavailable payloads', () {
      expect(
        PoiDiscoveryResult.fromFunctionPayload({'available': false}),
        isNull,
      );
    });
  });
}

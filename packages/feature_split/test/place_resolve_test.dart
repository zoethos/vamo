import 'package:feature_split/src/places/place_models.dart';
import 'package:feature_split/src/places/place_resolve.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolvePlaceCoordinates', () {
    test('agreement within 500m yields both + high confidence', () {
      const geocoded = GeocodeCoords(lat: 45.4642, lng: 9.1900);
      final result = resolvePlaceCoordinates(
        geocoded: geocoded,
        exifLat: 45.46425,
        exifLng: 9.19005,
      );
      expect(result, isNotNull);
      expect(result!.source, 'both');
      expect(result.confidence, greaterThanOrEqualTo(0.8));
      expect(result.lat, 45.46425);
    });

    test('conflict uses EXIF coords and keeps address text', () {
      const geocoded = GeocodeCoords(lat: 48.8566, lng: 2.3522);
      final result = resolvePlaceCoordinates(
        geocoded: geocoded,
        exifLat: 45.0,
        exifLng: 9.0,
      );
      expect(result, isNotNull);
      expect(result!.source, 'exif');
      expect(result.keepAddressText, isTrue);
      expect(result.lat, 45.0);
    });

    test('receipt geocode only yields receipt source', () {
      const geocoded = GeocodeCoords(lat: 41.9028, lng: 12.4964);
      final result = resolvePlaceCoordinates(geocoded: geocoded);
      expect(result, isNotNull);
      expect(result!.source, 'receipt');
      expect(result.confidence, 0.6);
    });

    test('EXIF only when geocode missing', () {
      final result = resolvePlaceCoordinates(exifLat: 47.3769, exifLng: 8.5417);
      expect(result, isNotNull);
      expect(result!.source, 'exif');
    });
  });

  group('findDuplicatePlaceId', () {
    const existing = [
      PlaceSummary(
        id: 'p1',
        tripId: 't1',
        label: 'Caffè Centrale',
        lat: 45.0,
        lng: 9.0,
        source: 'receipt',
        confidence: 0.6,
      ),
    ];

    test('reuses place with same label within 100m', () {
      expect(
        findDuplicatePlaceId(
          existing: existing,
          label: 'caffè centrale',
          lat: 45.0004,
          lng: 9.0004,
        ),
        'p1',
      );
    });

    test('creates new place when far apart', () {
      expect(
        findDuplicatePlaceId(
          existing: existing,
          label: 'Caffè Centrale',
          lat: 46.0,
          lng: 10.0,
        ),
        isNull,
      );
    });
  });
}

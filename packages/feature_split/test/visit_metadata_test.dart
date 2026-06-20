import 'package:feature_split/src/plan/plan_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PlanItemKind.visit', () {
    test('parses from the postgres enum name', () {
      expect(PlanItemKind.parse('visit'), PlanItemKind.visit);
    });

    test('unknown values still fall back to other', () {
      expect(PlanItemKind.parse('nope'), PlanItemKind.other);
    });

    test('renders a place marker icon', () {
      expect(PlanItemKind.visit.icon, Icons.place_outlined);
    });
  });

  group('fallbackFor(visit)', () {
    final caps = PlanItemCapabilities.fallbackFor(PlanItemKind.visit);

    test('suggests POIs and shows a details form', () {
      expect(caps.suggestsPois, isTrue);
      expect(caps.hasDetailsForm, isTrue);
    });

    test('no RSVP or live status for a visit', () {
      expect(caps.supportsRsvp, isFalse);
      expect(caps.hasLiveStatus, isFalse);
    });
  });

  group('VisitPlaceMetadata', () {
    test('build trims, encode/parse round-trips a full place', () {
      final map = buildVisitPlaceMetadata(
        placeLabel: '  Trattoria da Enzo  ',
        address: '  Via dei Vascellari 29  ',
        lat: 41.8881,
        lng: 12.4762,
        placeId: 'place-123',
      );
      expect(map['place_label'], 'Trattoria da Enzo');
      expect(map['address'], 'Via dei Vascellari 29');

      final parsed = parseVisitPlaceMetadata(encodePlanMetadata(map));
      expect(parsed, isNotNull);
      expect(parsed!.placeLabel, 'Trattoria da Enzo');
      expect(parsed.address, 'Via dei Vascellari 29');
      expect(parsed.lat, closeTo(41.8881, 1e-9));
      expect(parsed.lng, closeTo(12.4762, 1e-9));
      expect(parsed.placeId, 'place-123');
      expect(parsed.hasCoords, isTrue);
    });

    test('omits empty optional fields', () {
      final map = buildVisitPlaceMetadata(placeLabel: 'Pantheon');
      expect(map.containsKey('address'), isFalse);
      expect(map.containsKey('lat'), isFalse);
      expect(map.containsKey('lng'), isFalse);
      expect(map.containsKey('place_id'), isFalse);

      final parsed = parseVisitPlaceMetadata(map);
      expect(parsed!.placeLabel, 'Pantheon');
      expect(parsed.hasCoords, isFalse);
    });

    test('returns null without a place_label', () {
      expect(parseVisitPlaceMetadata(<String, Object?>{'address': 'x'}), isNull);
      expect(parseVisitPlaceMetadata(null), isNull);
    });

    test('preserves unknown metadata keys (S49 object invariant)', () {
      final encoded = encodePlanMetadata(<String, Object?>{
        'place_label': 'Roman Forum',
        'future_key': 'keep-me',
      });
      expect(parsePlanMetadata(encoded)['future_key'], 'keep-me');
      expect(parseVisitPlaceMetadata(encoded)!.placeLabel, 'Roman Forum');
    });
  });
}

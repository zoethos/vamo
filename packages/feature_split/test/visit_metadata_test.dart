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

  group('PlanItemKind.transfer', () {
    test('parses from the postgres enum name', () {
      expect(PlanItemKind.parse('transfer'), PlanItemKind.transfer);
    });

    test('renders a transfer icon', () {
      expect(PlanItemKind.transfer.icon, Icons.sync_alt_outlined);
    });
  });

  group('fallbackFor(transfer)', () {
    final caps = PlanItemCapabilities.fallbackFor(PlanItemKind.transfer);

    test('has status, check-time, and details affordances', () {
      expect(caps.hasLiveStatus, isTrue);
      expect(caps.hasCheckTimes, isTrue);
      expect(caps.hasDetailsForm, isTrue);
    });

    test('does not RSVP or suggest POIs', () {
      expect(caps.supportsRsvp, isFalse);
      expect(caps.suggestsPois, isFalse);
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
      expect(
          parseVisitPlaceMetadata(<String, Object?>{'address': 'x'}), isNull);
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

  group('TransferMetadata', () {
    test('build trims, encode/parse round-trips a transfer', () {
      final map = buildTransferMetadata(
        subtype: TransferSubtype.carRental,
        origin: '  Napoli Centrale  ',
        destination: '  Amalfi  ',
        provider: '  Driver Luigi  ',
        reference: '  VAN-42  ',
      );
      expect(map, {
        'subtype': 'car_rental',
        'origin': 'Napoli Centrale',
        'destination': 'Amalfi',
        'provider': 'Driver Luigi',
        'reference': 'VAN-42',
      });

      final parsed = parseTransferMetadata(encodePlanMetadata(map));
      expect(parsed, isNotNull);
      expect(parsed!.subtype, TransferSubtype.carRental);
      expect(parsed.origin, 'Napoli Centrale');
      expect(parsed.destination, 'Amalfi');
      expect(parsed.provider, 'Driver Luigi');
      expect(parsed.reference, 'VAN-42');
    });

    test('omits empty optional fields', () {
      final map = buildTransferMetadata(
        subtype: TransferSubtype.transit,
        origin: '  ',
        destination: '',
      );
      expect(map, {'subtype': 'transit'});
      expect(parseTransferMetadata(map)!.subtype, TransferSubtype.transit);
    });

    test('requires subtype and maps legacy kinds', () {
      expect(parseTransferMetadata(<String, Object?>{'origin': 'x'}), isNull);
      expect(legacyTransferSubtypeForKind(PlanItemKind.flight),
          TransferSubtype.flight);
      expect(legacyTransferSubtypeForKind(PlanItemKind.train),
          TransferSubtype.train);
      expect(legacyTransferSubtypeForKind(PlanItemKind.visit), isNull);
    });
  });
}

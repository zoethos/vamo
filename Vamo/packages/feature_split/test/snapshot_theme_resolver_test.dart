import 'package:feature_split/src/snapshot/snapshot_themes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SnapshotThemes.resolve', () {
    test('matches Rome from destination', () {
      expect(
        SnapshotThemes.resolve(
          destination: 'Rome, Italy',
          tripName: 'Summer trip',
        ).id,
        'rome',
      );
    });

    test('matches Rome from trip name', () {
      expect(
        SnapshotThemes.resolve(
          destination: null,
          tripName: 'Weekend in Roma',
        ).id,
        'rome',
      );
    });

    test('matches coast keywords before default', () {
      expect(
        SnapshotThemes.resolve(
          destination: 'Positano, Amalfi Coast',
          tripName: 'Girls trip',
        ).id,
        'coast',
      );
    });

    test('matches Paris', () {
      expect(
        SnapshotThemes.resolve(
          destination: 'Paris',
          tripName: 'City break',
        ).id,
        'paris',
      );
    });

    test('falls back to default when no keyword hits', () {
      expect(
        SnapshotThemes.resolve(
          destination: 'Berlin',
          tripName: 'Work offsite',
        ).id,
        'default',
      );
    });

    test('Rome beats coast when both keywords present', () {
      expect(
        SnapshotThemes.resolve(
          destination: 'Rome beach day',
          tripName: 'Amalfi side trip',
        ).id,
        'rome',
      );
    });

    test('does not false-positive on substring matches', () {
      expect(
        SnapshotThemes.resolve(
          tripName: 'Romantic getaway',
        ).id,
        'default',
      );
      expect(
        SnapshotThemes.resolve(
          tripName: "Jerome's birthday",
        ).id,
        'default',
      );
      expect(
        SnapshotThemes.resolve(
          tripName: 'Aroma tasting tour',
        ).id,
        'default',
      );
    });

    test('matches coast with diacritics stripped from haystack', () {
      expect(
        SnapshotThemes.resolve(
          destination: "Côte d'Azur seaside",
          tripName: 'Summer',
        ).id,
        'coast',
      );
    });
  });
}

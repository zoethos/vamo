import 'package:app_core/src/units/distance_unit_provider.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakePersistence implements DistanceUnitPersistence {
  _FakePersistence([this._stored]);

  DistanceUnit? _stored;
  int writes = 0;

  @override
  Future<DistanceUnit?> read() async => _stored;

  @override
  Future<void> write(DistanceUnit unit) async {
    _stored = unit;
    writes++;
  }
}

void main() {
  group('DistanceUnit conversion', () {
    test('km is identity', () {
      expect(DistanceUnit.km.fromKm(600), 600);
      expect(DistanceUnit.km.toKm(600), 600);
    });

    test('miles round-trips through km', () {
      final miles = DistanceUnit.miles.fromKm(600);
      expect(miles, closeTo(372.82, 0.01));
      expect(DistanceUnit.miles.toKm(miles), closeTo(600, 0.0001));
    });

    test('parse is tolerant', () {
      expect(DistanceUnit.parse('miles'), DistanceUnit.miles);
      expect(DistanceUnit.parse('furlongs'), isNull);
      expect(DistanceUnit.parse(null), isNull);
    });
  });

  group('DistanceUnitController', () {
    test('defaults to km and loads a saved unit', () async {
      final fake = _FakePersistence(DistanceUnit.miles);
      final controller = DistanceUnitController(persistence: fake);
      expect(controller.state, DistanceUnit.km); // before async load
      await Future<void>.delayed(Duration.zero);
      expect(controller.state, DistanceUnit.miles); // after load
    });

    test('setUnit updates state and persists', () async {
      final fake = _FakePersistence();
      final controller = DistanceUnitController(persistence: fake);
      await controller.setUnit(DistanceUnit.miles);
      expect(controller.state, DistanceUnit.miles);
      expect(fake.writes, 1);
    });
  });
}

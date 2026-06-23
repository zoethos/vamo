import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../analytics/action_failure.dart';

/// User-facing distance unit. Reach limits and POI distances render in this
/// unit; values are always stored canonically in kilometres.
enum DistanceUnit {
  km,
  miles;

  static DistanceUnit? parse(String? raw) {
    if (raw == null) return null;
    for (final value in DistanceUnit.values) {
      if (value.name == raw) return value;
    }
    return null;
  }

  static const _kmPerMile = 1.609344;

  /// Convert canonical kilometres into this unit.
  double fromKm(double km) => this == DistanceUnit.km ? km : km / _kmPerMile;

  /// Convert a value in this unit back to canonical kilometres.
  double toKm(double value) =>
      this == DistanceUnit.km ? value : value * _kmPerMile;
}

abstract interface class DistanceUnitPersistence {
  Future<DistanceUnit?> read();
  Future<void> write(DistanceUnit unit);
}

class FileDistanceUnitPersistence implements DistanceUnitPersistence {
  const FileDistanceUnitPersistence();

  static const _fileName = 'vamo_distance_unit_preference.txt';

  @override
  Future<DistanceUnit?> read() async {
    final file = await _preferenceFile();
    if (file == null || !await file.exists()) return null;
    final raw = (await file.readAsString()).trim();
    return DistanceUnit.parse(raw);
  }

  @override
  Future<void> write(DistanceUnit unit) async {
    final file = await _preferenceFile();
    if (file == null) return;
    await file.writeAsString(unit.name);
  }

  static Future<File?> _preferenceFile() async {
    try {
      final dir = await getApplicationSupportDirectory();
      return File('${dir.path}/$_fileName');
    } catch (error, stackTrace) {
      reportAndLog(
        error,
        stackTrace,
        screen: 'settings',
        action: 'distance_unit_preference_file',
        severity: ActionFailureSeverity.degraded,
      );
      return null;
    }
  }
}

class NoopDistanceUnitPersistence implements DistanceUnitPersistence {
  const NoopDistanceUnitPersistence();

  @override
  Future<DistanceUnit?> read() async => null;

  @override
  Future<void> write(DistanceUnit unit) async {}
}

class DistanceUnitController extends StateNotifier<DistanceUnit> {
  DistanceUnitController({
    DistanceUnitPersistence persistence = const FileDistanceUnitPersistence(),
    DistanceUnit initialUnit = DistanceUnit.km,
  })  : _persistence = persistence,
        super(initialUnit) {
    unawaited(_load());
  }

  final DistanceUnitPersistence _persistence;

  Future<void> _load() async {
    final saved = await _persistence.read();
    if (saved != null) state = saved;
  }

  Future<void> setUnit(DistanceUnit unit) async {
    state = unit;
    await _persistence.write(unit);
  }
}

/// Defaults to km (metric); miles is opt-in via Profile › Preferences.
final distanceUnitProvider =
    StateNotifierProvider<DistanceUnitController, DistanceUnit>(
  (ref) => DistanceUnitController(),
);

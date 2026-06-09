import 'dart:io';

import 'package:feature_split/src/trips/trip_background_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'platform_test_support.dart';

void main() {
  test('persist returns a new hero path on each write', () async {
    setUpFakePathProvider();
    addTearDown(tearDownFakePathProvider);

    final source = p.normalize(
      p.join(Directory.current.path, 'test', 'fixtures', 'hero_bg.png'),
    );
    expect(File(source).existsSync(), isTrue);

    const tripId = 'trip-storage-unique';
    final first = await TripBackgroundStorage.persist(
      tripId: tripId,
      sourcePath: source,
    );
    final second = await TripBackgroundStorage.persist(
      tripId: tripId,
      sourcePath: source,
    );

    expect(first, isNot(second));
    expect(p.basename(first), matches(RegExp(r'^hero_\d+\.png$')));
    expect(p.basename(second), matches(RegExp(r'^hero_\d+\.png$')));
    expect(File(first).existsSync(), isFalse);
    expect(File(second).existsSync(), isTrue);
  });
}

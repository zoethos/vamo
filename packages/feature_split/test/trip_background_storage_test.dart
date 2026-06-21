import 'dart:io';
import 'dart:typed_data';

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

  test('persistBytes does not require a readable source path', () async {
    setUpFakePathProvider();
    addTearDown(tearDownFakePathProvider);

    const tripId = 'trip-storage-bytes';
    final stored = await TripBackgroundStorage.persistBytes(
      tripId: tripId,
      sourceName: 'picked-from-photo-picker.jpg',
      bytes: Uint8List.fromList([1, 2, 3, 4]),
    );

    expect(p.basename(stored), matches(RegExp(r'^hero_\d+\.jpg$')));
    expect(await File(stored).readAsBytes(), [1, 2, 3, 4]);
  });
}

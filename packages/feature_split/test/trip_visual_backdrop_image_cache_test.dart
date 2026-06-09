import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:feature_split/src/trips/trip_background_storage.dart';
import 'package:feature_split/src/trips/trip_visual_backdrop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

Future<void> _writeSolidPng(String path, Color color) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(const Rect.fromLTWH(0, 0, 4, 4), Paint()..color = color);
  final picture = recorder.endRecording();
  final image = await picture.toImage(4, 4);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  await File(path).writeAsBytes(bytes!.buffer.asUint8List());
  image.dispose();
  picture.dispose();
}

Future<Color> _resolveCenterColor(FileImage provider) async {
  final completer = Completer<Color>();
  final stream = provider.resolve(ImageConfiguration.empty);
  late ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) async {
      final data =
          await info.image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final pixels = data!.buffer.asUint8List();
      const offset = (2 * 4 + 2) * 4;
      if (!completer.isCompleted) {
        completer.complete(
          Color.fromARGB(
            pixels[offset + 3],
            pixels[offset],
            pixels[offset + 1],
            pixels[offset + 2],
          ),
        );
      }
      stream.removeListener(listener);
    },
    onError: completer.completeError,
  );
  stream.addListener(listener);
  return completer.future.timeout(const Duration(seconds: 5));
}

Future<Color> _readFileCenterColor(String path) async {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromList(
    await File(path).readAsBytes(),
    completer.complete,
  );
  final image = await completer.future;
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final pixels = data!.buffer.asUint8List();
  const offset = (2 * 4 + 2) * 4;
  return Color.fromARGB(
    pixels[offset + 3],
    pixels[offset],
    pixels[offset + 1],
    pixels[offset + 2],
  );
}

bool _isDominantRed(Color color) =>
    color.red > color.blue && color.red > color.green;

bool _isDominantBlue(Color color) =>
    color.blue > color.red && color.blue > color.green;

void _clearImageCache() {
  PaintingBinding.instance.imageCache.clear();
  PaintingBinding.instance.imageCache.clearLiveImages();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(_clearImageCache);

  test('FileImage serves stale bytes for same path until cache evicted', () async {
    final dir = await Directory.systemTemp.createTemp('hero_cache_test_');
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } on FileSystemException {
        // Windows may still hold open handles briefly.
      }
    });
    final path = p.join(dir.path, 'hero.jpg');
    final provider = FileImage(File(path));

    await _writeSolidPng(path, Colors.red);
    final first = await _resolveCenterColor(provider);
    expect(_isDominantRed(first), isTrue);

    await _writeSolidPng(path, Colors.blue);
    final stale = await _resolveCenterColor(provider);
    expect(_isDominantRed(stale), isTrue);

    await TripBackgroundStorage.evictHeroImageCache(path);
    final fresh = await _resolveCenterColor(provider);
    expect(_isDominantBlue(fresh), isTrue);
  });

  testWidgets('TripVisualBackdrop rebuilds after same-path overwrite and evict', (
    tester,
  ) async {
    final dir = await Directory.systemTemp.createTemp('hero_backdrop_test_');
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } on FileSystemException {
        // Windows may still hold open handles briefly.
      }
    });
    final path = p.join(dir.path, 'hero.jpg');

    await _writeSolidPng(path, Colors.red);
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 4,
          height: 4,
          child: TripVisualBackdrop(
            tripName: 'Test trip',
            backgroundImagePath: path,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(Image), findsOneWidget);

    await _writeSolidPng(path, Colors.blue);
    await TripBackgroundStorage.evictHeroImageCache(path);

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 4,
          height: 4,
          child: TripVisualBackdrop(
            key: const ValueKey('second'),
            tripName: 'Test trip',
            backgroundImagePath: path,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(Image), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    _clearImageCache();

    expect(_isDominantBlue(await _readFileCenterColor(path)), isTrue);
  });
}

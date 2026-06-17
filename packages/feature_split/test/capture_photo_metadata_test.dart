import 'package:feature_split/src/capture/capture_photo_metadata.dart';
import 'package:feature_split/src/media/media_metadata.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'capture photo metadata resolver is skipped when tagging is off',
    () async {
      var called = false;

      final metadata = await resolveCapturePhotoMetadata(
        tagCaptureLocation: false,
        localPath: '/tmp/does-not-exist.jpg',
        resolver: (_) async {
          called = true;
          return const MediaCaptureMetadata(lat: 1, lng: 2, capturedAt: null);
        },
      );

      expect(called, isFalse);
      expect(metadata.lat, isNull);
      expect(metadata.lng, isNull);
      expect(metadata.capturedAt, isNull);
    },
  );

  test('capture photo metadata resolver runs when tagging is on', () async {
    final metadata = await resolveCapturePhotoMetadata(
      tagCaptureLocation: true,
      localPath: '/tmp/photo.jpg',
      resolver: (_) async => MediaCaptureMetadata(
        lat: 48.8566,
        lng: 2.3522,
        capturedAt: DateTime.utc(2026, 5, 4, 8),
      ),
    );

    expect(metadata.lat, 48.8566);
    expect(metadata.lng, 2.3522);
    expect(metadata.capturedAt, DateTime.utc(2026, 5, 4, 8));
  });
}

import 'package:feature_split/src/capture/capture_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('buildCaptureSnapshotHighlight picks latest note and 3 photos', () {
    final highlight = buildCaptureSnapshotHighlight(
      notes: [
        TripNoteView(
          id: '1',
          tripId: 't',
          title: 'Day 1',
          body:
              'Long body text that should be excerpted when it exceeds eighty characters in total length here.',
          capturedAt: DateTime.utc(2026, 6, 2),
        ),
      ],
      photos: List.generate(
        4,
        (i) => TripPhotoView(
          id: '$i',
          tripId: 't',
          displayPath: '/tmp/$i.jpg',
          capturedAt: DateTime.utc(2026, 6, 1),
        ),
      ),
    );

    expect(highlight.noteTitle, 'Day 1');
    expect(highlight.noteExcerpt, endsWith('…'));
    expect(highlight.photoPaths, ['/tmp/0.jpg', '/tmp/1.jpg', '/tmp/2.jpg']);
  });
}

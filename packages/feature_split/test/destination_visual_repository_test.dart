import 'dart:convert';

import 'package:feature_split/src/trips/destination_visual_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('DestinationVisual parses Foursquare image URL payload', () {
    final visual = DestinationVisual.fromPayload({
      'available': true,
      'source': 'foursquare',
      'imageUrl': 'https://img.example/amalfi.jpg',
      'title': 'Amalfi',
      'subtitle': 'Campania, Italy',
    });

    expect(visual?.source, 'foursquare');
    expect(visual?.imageUrl, 'https://img.example/amalfi.jpg');
    expect(visual?.imageBytes, isNull);
    expect(visual?.hasImage, isTrue);
  });

  test('DestinationVisual parses AI base64 payload', () {
    final visual = DestinationVisual.fromPayload({
      'available': true,
      'source': 'ai',
      'imageBase64': base64Encode([1, 2, 3]),
      'mimeType': 'image/png',
      'title': 'Amalfi Coast',
    });

    expect(visual?.source, 'ai');
    expect(visual?.imageBytes, [1, 2, 3]);
    expect(visual?.sourceName, 'destination-ai.png');
  });

  test('DestinationVisual ignores payloads without images', () {
    expect(
      DestinationVisual.fromPayload({
        'available': true,
        'source': 'foursquare',
      }),
      isNull,
    );
  });
}

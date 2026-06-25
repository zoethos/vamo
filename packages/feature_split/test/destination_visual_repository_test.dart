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
      'attribution': 'Foursquare Places API live response',
    });

    expect(visual?.source, 'foursquare');
    expect(visual?.imageUrl, 'https://img.example/amalfi.jpg');
    expect(visual?.imageBytes, isNull);
    expect(visual?.hasImage, isTrue);
    expect(visual?.attribution, 'Foursquare Places API live response');
  });

  test('DestinationVisual parses static-map base64 payload', () {
    final visual = DestinationVisual.fromPayload({
      'available': true,
      'source': 'static_map',
      'imageBase64': base64Encode([1, 2, 3]),
      'mimeType': 'image/png',
      'title': 'Amalfi Coast',
    });

    expect(visual?.source, 'static_map');
    expect(visual?.imageBytes, [1, 2, 3]);
    expect(visual?.sourceName, 'destination-static_map.png');
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

import 'dart:convert';
import 'dart:typed_data';

import 'package:app_core/app_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final destinationVisualRepositoryProvider =
    Provider<DestinationVisualRepository>((ref) {
  return DestinationVisualRepository(
    client: ref.watch(supabaseClientProvider),
    analytics: ref.watch(analyticsProvider),
  );
});

class DestinationVisualRepository {
  DestinationVisualRepository({
    required SupabaseClient client,
    Analytics? analytics,
  })  : _client = client,
        _analytics = analytics;

  final SupabaseClient _client;
  final Analytics? _analytics;

  Future<DestinationVisual?> resolve({
    required String destination,
    double? lat,
    double? lng,
    String? tripId,
    String? observationKind,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'destination-visual',
        body: {
          'destination': destination.trim(),
          if (lat != null) 'lat': lat,
          if (lng != null) 'lng': lng,
          if (tripId != null) 'trip_id': tripId,
          if (observationKind != null) 'observation_kind': observationKind,
        },
      ).timeout(const Duration(seconds: 16));

      if (response.status != 200) return null;
      return DestinationVisual.fromPayload(response.data);
    } catch (error, stackTrace) {
      reportAndLog(
        error,
        stackTrace,
        screen: 'create_trip',
        action: 'destination_visual',
        severity: ActionFailureSeverity.degraded,
        analytics: _analytics,
      );
      return null;
    }
  }
}

class DestinationVisual {
  const DestinationVisual({
    required this.source,
    this.imageUrl,
    this.imageBytes,
    this.mimeType,
    this.title,
    this.subtitle,
    this.attribution,
  });

  final String source;
  final String? imageUrl;
  final Uint8List? imageBytes;
  final String? mimeType;
  final String? title;
  final String? subtitle;
  final String? attribution;

  bool get hasImage =>
      imageBytes != null || (imageUrl != null && imageUrl!.isNotEmpty);

  String get sourceName {
    final extension = switch (mimeType) {
      'image/png' => 'png',
      'image/webp' => 'webp',
      _ => 'jpg',
    };
    return 'destination-$source.$extension';
  }

  static DestinationVisual? fromPayload(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    if (map['available'] != true) return null;
    final source = _stringValue(map['source']) ?? 'destination';
    final imageUrl = _stringValue(map['imageUrl']);
    final imageBase64 = _stringValue(map['imageBase64']);
    final bytes = imageBase64 == null ? null : _decodeBase64(imageBase64);
    final visual = DestinationVisual(
      source: source,
      imageUrl: imageUrl,
      imageBytes: bytes,
      mimeType: _stringValue(map['mimeType']),
      title: _stringValue(map['title']),
      subtitle: _stringValue(map['subtitle']),
      attribution: _stringValue(map['attribution']),
    );
    return visual.hasImage ? visual : null;
  }

  static Uint8List? _decodeBase64(String raw) {
    try {
      return base64Decode(raw);
    } on FormatException {
      return null;
    }
  }
}

String? _stringValue(Object? raw) {
  if (raw is! String) return null;
  final trimmed = raw.trim();
  return trimmed.isEmpty ? null : trimmed;
}

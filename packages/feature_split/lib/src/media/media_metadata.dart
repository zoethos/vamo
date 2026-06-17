import 'dart:io';

import 'package:app_core/app_core.dart';
import 'package:exif/exif.dart';

/// GPS + timestamp extracted from image EXIF.
///
/// Device GPS capture and video metadata are separate follow-up slices.
class MediaCaptureMetadata {
  const MediaCaptureMetadata({this.lat, this.lng, this.capturedAt});

  final double? lat;
  final double? lng;
  final DateTime? capturedAt;

  bool get hasLocation => lat != null && lng != null;
}

/// Reads EXIF GPS/timestamp when present; otherwise returns empty metadata.
Future<MediaCaptureMetadata> resolveMediaMetadata(
  String imagePath, {
  String screen = 'media',
  String action = 'read_media_metadata',
}) async {
  try {
    final tags = await readExifFromFile(File(imagePath));
    if (tags.isEmpty) return const MediaCaptureMetadata();

    final lat = _gpsCoordinate(
      tags['GPS GPSLatitude'],
      tags['GPS GPSLatitudeRef']?.printable,
    );
    final lng = _gpsCoordinate(
      tags['GPS GPSLongitude'],
      tags['GPS GPSLongitudeRef']?.printable,
    );
    final capturedAt = _exifDateTime(tags);

    return MediaCaptureMetadata(
      lat: lat,
      lng: lng,
      capturedAt: capturedAt?.toUtc(),
    );
  } catch (error, stackTrace) {
    reportAndLog(
      error,
      stackTrace,
      screen: screen,
      action: action,
      severity: ActionFailureSeverity.degraded,
    );
    return const MediaCaptureMetadata();
  }
}

double? _gpsCoordinate(IfdTag? tag, String? ref) {
  if (tag == null || ref == null || ref.isEmpty) return null;
  final list = tag.values.toList();
  if (list.length < 3) return null;

  double part(int index) {
    final value = list[index];
    if (value is Ratio) return value.toDouble();
    if (value is num) return value.toDouble();
    return 0;
  }

  var decimal = part(0) + part(1) / 60 + part(2) / 3600;
  final hemisphere = ref.toUpperCase();
  if (hemisphere == 'S' || hemisphere == 'W') {
    decimal = -decimal;
  }
  return decimal;
}

DateTime? _exifDateTime(Map<String, IfdTag> tags) {
  for (final key in ['EXIF DateTimeOriginal', 'Image DateTime']) {
    final raw = tags[key]?.printable;
    if (raw == null || raw.isEmpty) continue;
    final parsed = _parseExifDateTime(raw);
    if (parsed != null) return parsed;
  }
  return null;
}

DateTime? _parseExifDateTime(String raw) {
  final match = RegExp(
    r'^(\d{4}):(\d{2}):(\d{2}) (\d{2}):(\d{2}):(\d{2})',
  ).firstMatch(raw.trim());
  if (match == null) return null;
  return DateTime(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
    int.parse(match.group(4)!),
    int.parse(match.group(5)!),
    int.parse(match.group(6)!),
  );
}

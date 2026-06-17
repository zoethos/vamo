import 'dart:io';
import 'dart:typed_data';

import 'package:feature_split/src/media/media_metadata.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('resolveMediaMetadata reads EXIF GPS and original timestamp', () async {
    final tempDir = await Directory.systemTemp.createTemp('vamo-exif-test');
    addTearDown(() => tempDir.delete(recursive: true));
    final file = File('${tempDir.path}/photo.tiff');
    await file.writeAsBytes(_tiffWithExifGps());

    final metadata = await resolveMediaMetadata(file.path);

    expect(metadata.hasLocation, isTrue);
    expect(metadata.lat, closeTo(40.7127777778, 0.000001));
    expect(metadata.lng, closeTo(-74.0058333333, 0.000001));
    expect(metadata.capturedAt, DateTime(2026, 5, 4, 8, 9, 10).toUtc());
  });

  test(
    'resolveMediaMetadata returns empty metadata for files without EXIF',
    () async {
      final tempDir = await Directory.systemTemp.createTemp('vamo-exif-empty');
      addTearDown(() => tempDir.delete(recursive: true));
      final file = File('${tempDir.path}/empty.jpg');
      await file.writeAsBytes(const [0xFF, 0xD8, 0xFF, 0xD9]);

      final metadata = await resolveMediaMetadata(file.path);

      expect(metadata.lat, isNull);
      expect(metadata.lng, isNull);
      expect(metadata.capturedAt, isNull);
    },
  );
}

Uint8List _tiffWithExifGps() {
  const ifd0Offset = 8;
  const exifIfdOffset = 38;
  const dateOffset = 56;
  const gpsIfdOffset = 76;
  const latOffset = 130;
  const lngOffset = 154;
  final bytes = Uint8List(178);
  final data = ByteData.sublistView(bytes);

  void u16(int offset, int value) {
    data.setUint16(offset, value, Endian.little);
  }

  void u32(int offset, int value) {
    data.setUint32(offset, value, Endian.little);
  }

  void entry(
    int offset, {
    required int tag,
    required int type,
    required int count,
    required int valueOrOffset,
  }) {
    u16(offset, tag);
    u16(offset + 2, type);
    u32(offset + 4, count);
    u32(offset + 8, valueOrOffset);
  }

  void asciiValue(int offset, String value) {
    final codes = value.codeUnits;
    for (var i = 0; i < codes.length; i++) {
      bytes[offset + i] = codes[i];
    }
  }

  void rational(int offset, int numerator, int denominator) {
    u32(offset, numerator);
    u32(offset + 4, denominator);
  }

  bytes[0] = 0x49;
  bytes[1] = 0x49;
  u16(2, 42);
  u32(4, ifd0Offset);

  u16(ifd0Offset, 2);
  entry(10, tag: 0x8769, type: 4, count: 1, valueOrOffset: exifIfdOffset);
  entry(22, tag: 0x8825, type: 4, count: 1, valueOrOffset: gpsIfdOffset);
  u32(34, 0);

  u16(exifIfdOffset, 1);
  entry(40, tag: 0x9003, type: 2, count: 20, valueOrOffset: dateOffset);
  u32(52, 0);
  asciiValue(dateOffset, '2026:05:04 08:09:10\u0000');

  u16(gpsIfdOffset, 4);
  entry(78, tag: 0x0001, type: 2, count: 2, valueOrOffset: 0x0000004E);
  entry(90, tag: 0x0002, type: 5, count: 3, valueOrOffset: latOffset);
  entry(102, tag: 0x0003, type: 2, count: 2, valueOrOffset: 0x00000057);
  entry(114, tag: 0x0004, type: 5, count: 3, valueOrOffset: lngOffset);
  u32(126, 0);

  rational(latOffset, 40, 1);
  rational(latOffset + 8, 42, 1);
  rational(latOffset + 16, 46, 1);
  rational(lngOffset, 74, 1);
  rational(lngOffset + 8, 0, 1);
  rational(lngOffset + 16, 21, 1);

  return bytes;
}

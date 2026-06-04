import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

/// Rasterizes a [RepaintBoundary] to PNG bytes for the system share sheet.
Future<Uint8List> captureRepaintBoundaryToPng(
  RenderRepaintBoundary boundary, {
  double pixelRatio = 3,
}) async {
  final image = await boundary.toImage(pixelRatio: pixelRatio);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  if (byteData == null) {
    throw StateError('Could not encode snapshot PNG');
  }
  return byteData.buffer.asUint8List();
}

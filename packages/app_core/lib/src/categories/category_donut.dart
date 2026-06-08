import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'category_donut_math.dart';

/// Zero-dependency ring chart for category spend share (S35).
class CategoryDonut extends StatelessWidget {
  const CategoryDonut({
    super.key,
    required this.slices,
    this.size = 72,
    this.strokeWidth = 10,
    this.gapRadians = 0.04,
  });

  final List<CategoryDonutSlice> slices;
  final double size;
  final double strokeWidth;
  final double gapRadians;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _CategoryDonutPainter(
          slices: slices,
          strokeWidth: strokeWidth,
          gapRadians: gapRadians,
        ),
      ),
    );
  }
}

class _CategoryDonutPainter extends CustomPainter {
  _CategoryDonutPainter({
    required this.slices,
    required this.strokeWidth,
    required this.gapRadians,
  });

  final List<CategoryDonutSlice> slices;
  final double strokeWidth;
  final double gapRadians;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    if (slices.isEmpty) {
      final paint = Paint()
        ..color = Colors.black.withValues(alpha: 0.08)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(rect, 0, math.pi * 2, false, paint);
      return;
    }

    var start = -math.pi / 2;
    final visible = slices.where((s) => s.fraction > 0).toList(growable: false);
    final gap = visible.length > 1 ? gapRadians : 0.0;

    for (var i = 0; i < visible.length; i++) {
      final slice = visible[i];
      final sweep = math.max(slice.fraction * math.pi * 2 - gap, 0.01);
      final paint = Paint()
        ..color = slice.entry.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(rect, start + gap / 2, sweep, false, paint);
      start += slice.fraction * math.pi * 2;
    }
  }

  @override
  bool shouldRepaint(covariant _CategoryDonutPainter oldDelegate) {
    return oldDelegate.slices != slices ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}

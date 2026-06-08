import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('gradient scrim bottom meets contrast for white title text', () {
    final scrimBottom = Colors.black.withValues(alpha: 0.72);
    expect(
      AppColors.contrastRatio(Colors.white, scrimBottom),
      greaterThan(4.5),
    );
  });
}

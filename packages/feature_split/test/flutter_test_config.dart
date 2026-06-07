import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await _loadGoldenFonts();
  goldenFileComparator = _TolerantLocalFileComparator(
    Uri.parse('test/flutter_test_config.dart'),
  );
  await testMain();
}

Future<void> _loadGoldenFonts() async {
  const fonts = {
    'NotoSans': 'NotoSans-Regular.ttf',
    'NotoSansArabic': 'NotoSansArabic-Regular.ttf',
    'NotoSansHebrew': 'NotoSansHebrew-Regular.ttf',
    'NotoSansSC': 'NotoSansSC-Regular.ttf',
    'NotoSansDevanagari': 'NotoSansDevanagari-Regular.ttf',
  };

  for (final entry in fonts.entries) {
    final loader = FontLoader(entry.key);
    final file = File('test/fonts/${entry.value}');
    if (!file.existsSync()) {
      throw StateError('Missing golden test font: ${file.path}');
    }
    loader.addFont(
      Future.value(ByteData.view(file.readAsBytesSync().buffer)),
    );
    await loader.load();
  }
}

/// Allows tiny platform/engine anti-alias drift while still failing real
/// visual regressions. Most goldens stay under 1%; S27 members invite is
/// ~1.6% between Linux CI and Windows dev hosts.
class _TolerantLocalFileComparator extends LocalFileComparator {
  _TolerantLocalFileComparator(super.testFile);

  static const _maxDiffPercent = 0.02;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );

    if (result.passed || result.diffPercent <= _maxDiffPercent) {
      result.dispose();
      return true;
    }

    final error = await generateFailureOutput(result, golden, basedir);
    result.dispose();
    throw FlutterError(error);
  }
}

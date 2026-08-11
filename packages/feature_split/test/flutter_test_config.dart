import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'platform_test_support.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await _loadGoldenFonts();
  goldenFileComparator = _TolerantLocalFileComparator(
    Uri.parse('test/flutter_test_config.dart'),
  );
  setUp(setUpFakePathProvider);
  tearDown(tearDownFakePathProvider);
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
    loader.addFont(Future.value(ByteData.view(file.readAsBytesSync().buffer)));
    await loader.load();
  }

  final materialFonts = Directory(
    '${_flutterRoot()}/bin/cache/artifacts/material_fonts',
  );
  await _loadFlutterFont(
    family: 'MaterialIcons',
    directory: materialFonts,
    candidates: const [
      'MaterialIcons-Regular.otf',
      'materialicons-regular.otf',
    ],
  );
  await _loadFlutterFont(
    family: 'Roboto',
    directory: materialFonts,
    candidates: const ['Roboto-Regular.ttf', 'roboto-regular.ttf'],
  );
  await _loadFlutterFont(
    family: 'Roboto',
    directory: materialFonts,
    candidates: const ['Roboto-Medium.ttf', 'roboto-medium.ttf'],
  );
  await _loadFlutterFont(
    family: 'Roboto',
    directory: materialFonts,
    candidates: const ['Roboto-Bold.ttf', 'roboto-bold.ttf'],
  );
}

Future<void> _loadFlutterFont({
  required String family,
  required Directory directory,
  required List<String> candidates,
}) async {
  File? file;
  for (final candidate in candidates) {
    final candidateFile = File('${directory.path}/$candidate');
    if (candidateFile.existsSync()) {
      file = candidateFile;
      break;
    }
  }
  if (file == null) {
    throw StateError('Missing $family font in ${directory.path}');
  }
  final loader = FontLoader(family);
  loader.addFont(Future.value(ByteData.view(file.readAsBytesSync().buffer)));
  await loader.load();
}

String _flutterRoot() {
  final fromEnv = Platform.environment['FLUTTER_ROOT'];
  if (fromEnv != null && fromEnv.isNotEmpty) return fromEnv;
  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 5; i++) {
    dir = dir.parent;
  }
  return dir.path;
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

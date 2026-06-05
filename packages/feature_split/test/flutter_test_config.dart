import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await _loadGoldenFonts();
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

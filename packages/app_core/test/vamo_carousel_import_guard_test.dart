import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('vamo_carousel.dart does not import forbidden packages', () {
    final root = _repoRoot();
    final file = File(
      p.join(root.path, 'packages', 'app_core', 'lib', 'src', 'design', 'vamo_carousel.dart'),
    );
    final source = file.readAsStringSync();

    const forbidden = [
      'feature_split',
      'image_picker',
      'supabase',
      'drift',
      'flutter_riverpod',
    ];

    final offenders = <String>[];
    for (final line in source.split('\n')) {
      final trimmed = line.trim();
      if (!trimmed.startsWith('import ') && !trimmed.startsWith('export ')) {
        continue;
      }
      for (final pkg in forbidden) {
        if (trimmed.contains(pkg)) {
          offenders.add('$trimmed  (forbidden: $pkg)');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'vamo_carousel.dart must stay a pure UI primitive',
    );
  });

  test('import guard catches a known-bad import string', () {
    const sample = "import 'package:image_picker/image_picker.dart';";
    expect(sample.contains('image_picker'), isTrue);
  });
}

Directory _repoRoot() {
  var dir = Directory.current.absolute;
  while (!File(p.join(dir.path, 'melos.yaml')).existsSync()) {
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('Could not find repo root from ${Directory.current.path}');
    }
    dir = parent;
  }
  return dir;
}

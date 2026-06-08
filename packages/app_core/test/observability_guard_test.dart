import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('lib code does not silently swallow catch blocks', () {
    final root = _repoRoot();
    final offenders = <String>[];

    for (final file in _libDartFiles(root)) {
      final source = file.readAsStringSync();
      final rel = p.relative(file.path, from: root.path);
      if (_bareCatch.hasMatch(source)) {
        offenders.add('$rel uses catch (_)');
      }
      if (_emptyCatch.hasMatch(source)) {
        offenders.add('$rel has an empty catch body');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'Use reportAndLog(error, stackTrace, screen/action, severity) '
          'for degraded failures instead of swallowing exceptions.',
    );
  });
}

final _bareCatch = RegExp(r'catch\s*\(\s*_\s*(?:,\s*_\s*)?\)');
final _emptyCatch = RegExp(
  r'catch\s*(?:\([^)]*\))?\s*\{\s*(?://[^\r\n]*)?\s*\}',
  multiLine: true,
);

Directory _repoRoot() {
  var dir = Directory.current.absolute;
  while (!File(p.join(dir.path, 'melos.yaml')).existsSync()) {
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError(
          'Could not find repo root from ${Directory.current.path}');
    }
    dir = parent;
  }
  return dir;
}

Iterable<File> _libDartFiles(Directory root) sync* {
  final dirs = [
    Directory(p.join(root.path, 'app', 'lib')),
    Directory(p.join(root.path, 'packages', 'app_core', 'lib')),
    Directory(p.join(root.path, 'packages', 'feature_split', 'lib')),
  ];

  for (final dir in dirs) {
    if (!dir.existsSync()) continue;
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is! File) continue;
      if (!entity.path.endsWith('.dart')) continue;
      if (entity.path.endsWith('.g.dart')) continue;
      yield entity;
    }
  }
}

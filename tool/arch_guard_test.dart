import 'dart:io';

import 'arch_guard.dart';

void main() {
  final cleanRule = const GuardRule(
    name: 'test pure boundary',
    paths: ['lib/pure.dart'],
    forbiddenImports: [
      ForbiddenImport(
        'package:drift/',
        reason: 'pure files must not import Drift',
      ),
      ForbiddenImport(
        'package:app_core/infra.dart',
        reason: 'pure files must not import infra',
      ),
    ],
  );

  final badIssues = findViolationsInSource(
    source: [
      "import 'dart:math';",
      "import 'package:drift/drift.dart';",
      "import 'package:app_core/infra.dart';",
      '',
      'int addOne(int value) => value + 1;',
    ].join('\n'),
    relativePath: 'lib/pure.dart',
    rule: cleanRule,
  );

  _expect(
    badIssues.length == 2,
    'expected two planted bad imports to be caught, got ${badIssues.length}',
  );
  _expect(
    badIssues.any((issue) => issue.forbiddenPattern == 'package:drift/'),
    'expected Drift import violation',
  );
  _expect(
    badIssues.any(
      (issue) => issue.forbiddenPattern == 'package:app_core/infra.dart',
    ),
    'expected infra sub-barrel import violation',
  );

  final cleanIssues = findViolationsInSource(
    source: [
      "import 'dart:math';",
      '',
      'int addOne(int value) => value + 1;',
    ].join('\n'),
    relativePath: 'lib/pure.dart',
    rule: cleanRule,
  );
  _expect(cleanIssues.isEmpty, 'expected clean source to pass');

  final directCallIssues = findDirectSupabaseCallViolationsInSource(
    source: [
      "final rows = _client.from('expenses').select();",
      "final result = client.rpc('commit_expense');",
      'final copy = Map<String, Object?>.from({});',
    ].join('\n'),
    relativePath:
        'packages/feature_split/lib/src/expenses/expenses_overview.dart',
  );
  _expect(
    directCallIssues.length == 2,
    'expected two direct Supabase calls outside an allowed file',
  );

  final repositoryCalls = findDirectSupabaseCallViolationsInSource(
    source: [
      "final rows = _client.from('expenses').select();",
      "final result = client.rpc('commit_expense');",
    ].join('\n'),
    relativePath:
        'packages/feature_split/lib/src/expenses/expenses_repository.dart',
  );
  _expect(repositoryCalls.isEmpty, 'expected repository calls to pass');

  final workerCalls = findDirectSupabaseCallViolationsInSource(
    source: "await _client.rpc('insert_committed_expense');",
    relativePath: 'packages/app_core/lib/src/sync/sync_worker.dart',
  );
  _expect(workerCalls.isEmpty, 'expected sync worker calls to pass');

  final tempRoot = Directory.systemTemp.createTempSync('vamo_arch_guard_');
  try {
    final scanRoot = Directory('${tempRoot.path}/packages/feature_split/lib');
    scanRoot.createSync(recursive: true);
    File('${tempRoot.path}/melos.yaml').writeAsStringSync('name: test\n');
    File(
      '${tempRoot.path}/tool_appcolors_baseline.txt',
    ).writeAsStringSync('1\n');
    File(
      '${scanRoot.path}/sample.dart',
    ).writeAsStringSync('const color = AppColors.ink;\n');

    final appColors = checkAppColorsBaseline(
      repoRoot: tempRoot,
      baselineRelativePath: 'tool_appcolors_baseline.txt',
      scanRootRelativePath: 'packages/feature_split/lib',
    );
    _expect(appColors.isPassing, 'expected AppColors baseline check to pass');
    _expect(appColors.count == 1, 'expected one AppColors ref');
  } finally {
    tempRoot.deleteSync(recursive: true);
  }

  stdout.writeln('arch-guard self-test passed');
}

List<GuardIssue> findDirectSupabaseCallViolationsInSource({
  required String source,
  required String relativePath,
}) {
  final tempRoot = Directory.systemTemp.createTempSync('vamo_arch_guard_call_');
  try {
    File('${tempRoot.path}/melos.yaml').writeAsStringSync('name: test\n');
    final file = File('${tempRoot.path}/$relativePath')
      ..createSync(recursive: true);
    file.writeAsStringSync(source);
    return findDirectSupabaseCallViolations(
      repoRoot: tempRoot,
      scanRoots: ['packages'],
    );
  } finally {
    tempRoot.deleteSync(recursive: true);
  }
}

void _expect(bool condition, String message) {
  if (condition) return;
  stderr.writeln('arch-guard self-test failed: $message');
  exit(1);
}

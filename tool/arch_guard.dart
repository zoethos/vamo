import 'dart:io';

const appColorsBaselinePath = 'tool/appcolors_baseline.txt';
const appColorsScanRoot = 'packages/feature_split/lib';
const directSupabaseScanRoots = ['app/lib', 'packages'];
final _methodInvocation = RegExp(
  r'\b([A-Za-z_$][A-Za-z0-9_$]*)\s*\.\s*(from|rpc)\s*\(',
);
final _typedSupabaseClient = RegExp(
  r'\bSupabaseClient\s+([A-Za-z_$][A-Za-z0-9_$]*)',
);
final _inferredSupabaseClient = RegExp(
  r'\b(?:final|var)\s+([A-Za-z_$][A-Za-z0-9_$]*)\s*='
  r'\s*(?:Supabase\.instance\.)?client\b',
);

const forbiddenPureImports = [
  ForbiddenImport(
    'dart:io',
    reason: 'pure/domain modules must not perform I/O',
  ),
  ForbiddenImport(
    'package:flutter/',
    reason: 'pure/domain modules must not import Flutter UI',
  ),
  ForbiddenImport(
    'package:drift/',
    reason: 'pure/domain modules must not import Drift',
  ),
  ForbiddenImport(
    'package:supabase',
    reason: 'pure/domain modules must not import Supabase clients',
  ),
  ForbiddenImport(
    'package:flutter_riverpod/',
    reason: 'pure/domain modules must not import Riverpod',
  ),
  ForbiddenImport(
    'package:image_picker/',
    reason: 'pure/domain modules must not import platform plugins',
  ),
  ForbiddenImport(
    'package:geocoding/',
    reason: 'pure/domain modules must not import platform plugins',
  ),
  ForbiddenImport(
    'package:google_mlkit',
    reason: 'pure/domain modules must not import platform plugins',
  ),
  ForbiddenImport(
    'package:mobile_scanner/',
    reason: 'pure/domain modules must not import platform plugins',
  ),
  ForbiddenImport(
    'package:path_provider/',
    reason: 'pure/domain modules must not import platform plugins',
  ),
  ForbiddenImport(
    'package:share_plus/',
    reason: 'pure/domain modules must not import platform plugins',
  ),
  ForbiddenImport(
    'package:url_launcher/',
    reason: 'pure/domain modules must not import platform plugins',
  ),
  ForbiddenImport(
    'package:app_core/infra.dart',
    reason: 'pure/domain modules must not import the infra sub-barrel',
  ),
];

const defaultRules = [
  GuardRule(
    name: 'pure/domain boundary',
    paths: [
      'packages/feature_split/lib/src/expenses/expense_split.dart',
      'packages/feature_split/lib/src/settle/settle_up.dart',
      'packages/feature_split/lib/src/expenses/receipt_ocr_parse.dart',
      'packages/feature_split/lib/src/expenses/receipt_ocr_form_prefill.dart',
      'packages/app_core/lib/src/fx/fx_math.dart',
      'packages/feature_split/lib/src/plan/event_rsvp_models.dart',
      'packages/app_core/lib/src/trips/trip_lifecycle.dart',
      'packages/feature_split/lib/src/trips/close_report_models.dart',
    ],
    forbiddenImports: forbiddenPureImports,
  ),
  // NOTE: the `app_core domain sub-barrel` rule is intentionally deferred until
  // the layered barrels (domain.dart / infra.dart) land. Re-add it then; see
  // docs/architecture/ARCHITECTURE_BOUNDARIES.md §5.
];

Future<void> main(List<String> args) async {
  if (args.contains('--help')) {
    stdout.writeln('Usage: dart run tool/arch_guard.dart [--repo-root <path>]');
    return;
  }

  final repoRootArg = _repoRootFromArgs(args);
  final repoRoot = repoRootArg == null
      ? findRepoRoot(Directory.current)
      : Directory(repoRootArg).absolute;
  final issues = findImportViolations(repoRoot: repoRoot, rules: defaultRules);
  final directSupabaseIssues = findDirectSupabaseCallViolations(
    repoRoot: repoRoot,
    scanRoots: directSupabaseScanRoots,
  );
  issues.addAll(directSupabaseIssues);

  final appColors = checkAppColorsBaseline(
    repoRoot: repoRoot,
    baselineRelativePath: appColorsBaselinePath,
    scanRootRelativePath: appColorsScanRoot,
  );

  if (issues.isEmpty && appColors.isPassing) {
    stdout.writeln(
      'arch-guard passed: ${defaultRules.length} import rules, '
      'direct Supabase calls confined to repositories/sync worker, '
      'AppColors ${appColors.count}/${appColors.baseline}.',
    );
    if (appColors.count < appColors.baseline) {
      stdout.writeln(
        'AppColors count is below baseline; lower '
        '$appColorsBaselinePath when this reduction is intentional.',
      );
    }
    return;
  }

  stderr.writeln('arch-guard failed.');
  for (final issue in issues) {
    stderr.writeln(issue.format());
  }
  if (!appColors.isPassing) {
    stderr.writeln(
      'AppColors ratchet failed: ${appColors.count} refs exceeds '
      'baseline ${appColors.baseline} in $appColorsScanRoot.',
    );
  }
  exitCode = 1;
}

Directory findRepoRoot(Directory start) {
  var dir = start.absolute;
  while (!File(_join(dir.path, 'melos.yaml')).existsSync()) {
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('Could not find repo root from ${start.path}');
    }
    dir = parent;
  }
  return dir;
}

List<GuardIssue> findImportViolations({
  required Directory repoRoot,
  required List<GuardRule> rules,
}) {
  final issues = <GuardIssue>[];
  for (final rule in rules) {
    for (final relativePath in rule.paths) {
      final file = File(_join(repoRoot.path, _normalize(relativePath)));
      if (!file.existsSync()) {
        issues.add(
          GuardIssue(
            ruleName: rule.name,
            relativePath: relativePath,
            lineNumber: 0,
            directive: '<missing file>',
            forbiddenPattern: '<missing file>',
            reason: 'guarded file is missing; update the manifest deliberately',
          ),
        );
        continue;
      }
      issues.addAll(
        findViolationsInSource(
          source: file.readAsStringSync(),
          relativePath: relativePath,
          rule: rule,
        ),
      );
    }
  }
  return issues;
}

List<GuardIssue> findViolationsInSource({
  required String source,
  required String relativePath,
  required GuardRule rule,
}) {
  final issues = <GuardIssue>[];
  final lines = source.split('\n');
  for (var index = 0; index < lines.length; index += 1) {
    final directive = lines[index].trim();
    if (!_isImportOrExportDirective(directive)) continue;

    for (final forbidden in rule.forbiddenImports) {
      if (directive.contains(forbidden.pattern)) {
        issues.add(
          GuardIssue(
            ruleName: rule.name,
            relativePath: relativePath,
            lineNumber: index + 1,
            directive: directive,
            forbiddenPattern: forbidden.pattern,
            reason: forbidden.reason,
          ),
        );
      }
    }
  }
  return issues;
}

/// Direct PostgREST calls are an infrastructure concern. Keep them in a
/// repository or the offline [SyncWorker], where retries and ownership are
/// already centralized. The matcher deliberately targets known Supabase client
/// receivers, not collection constructors such as `Map.from(...)`.
List<GuardIssue> findDirectSupabaseCallViolations({
  required Directory repoRoot,
  required List<String> scanRoots,
}) {
  final issues = <GuardIssue>[];
  for (final relativeRoot in scanRoots) {
    final root = Directory(_join(repoRoot.path, _normalize(relativeRoot)));
    if (!root.existsSync()) continue;
    for (final entity in root.listSync(recursive: true, followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final relativePath = _relativeTo(repoRoot.path, entity.path);
      if (_isDirectSupabaseCallAllowed(relativePath)) continue;
      final source = entity.readAsStringSync();
      final maskedSource = _maskDartNonCode(source);
      final receivers = _supabaseClientReceivers(maskedSource);
      final lines = source.split('\n');
      for (final match in _methodInvocation.allMatches(maskedSource)) {
        if (!receivers.contains(match.group(1))) continue;
        final lineNumber = _lineNumberAt(source, match.start);
        issues.add(
          GuardIssue(
            ruleName: 'direct Supabase boundary',
            relativePath: relativePath,
            lineNumber: lineNumber,
            directive: lines[lineNumber - 1].trim(),
            forbiddenPattern: match.group(0)!,
            reason: 'direct .from()/.rpc() calls belong in a *_repository.dart '
                'file or sync_worker.dart',
          ),
        );
      }
    }
  }
  return issues;
}

bool _isDirectSupabaseCallAllowed(String relativePath) {
  final normalized = relativePath.replaceAll('\\', '/');
  final fileName = normalized.split('/').last;
  return fileName.endsWith('_repository.dart') ||
      fileName == 'sync_worker.dart';
}

Set<String> _supabaseClientReceivers(String source) {
  return {
    for (final match in _typedSupabaseClient.allMatches(source))
      match.group(1)!,
    for (final match in _inferredSupabaseClient.allMatches(source))
      match.group(1)!,
  };
}

int _lineNumberAt(String source, int offset) =>
    '\n'.allMatches(source.substring(0, offset)).length + 1;

/// Masks comments and string literals while preserving every newline and
/// character offset, so diagnostics still point at the original source line.
String _maskDartNonCode(String source) {
  final chars = source.split('');
  var index = 0;
  while (index < chars.length) {
    final current = chars[index];
    final next = index + 1 < chars.length ? chars[index + 1] : '';
    if (current == '/' && next == '/') {
      index = _maskUntilNewline(chars, index);
    } else if (current == '/' && next == '*') {
      index = _maskBlockComment(chars, index);
    } else if (current == '\"' || current == "'") {
      index = _maskString(chars, index, current);
    } else {
      index += 1;
    }
  }
  return chars.join();
}

int _maskUntilNewline(List<String> chars, int start) {
  var index = start;
  while (index < chars.length && chars[index] != '\n') {
    chars[index] = ' ';
    index += 1;
  }
  return index;
}

int _maskBlockComment(List<String> chars, int start) {
  var index = start;
  while (index < chars.length) {
    final current = chars[index];
    final next = index + 1 < chars.length ? chars[index + 1] : '';
    if (current != '\n') chars[index] = ' ';
    index += 1;
    if (current == '*' && next == '/') {
      chars[index] = ' ';
      return index + 1;
    }
  }
  return index;
}

int _maskString(List<String> chars, int start, String quote) {
  final original = List<String>.from(chars);
  final triple = start + 2 < chars.length &&
      original[start + 1] == quote &&
      original[start + 2] == quote;
  final openingLength = triple ? 3 : 1;
  for (var openingIndex = 0; openingIndex < openingLength; openingIndex += 1) {
    chars[start + openingIndex] = ' ';
  }
  var index = start + openingLength;
  while (index < chars.length) {
    final escaped = original[index] == '\\';
    if (chars[index] != '\n') chars[index] = ' ';
    index += 1;
    if (escaped && index < chars.length) {
      if (chars[index] != '\n') chars[index] = ' ';
      index += 1;
      continue;
    }
    final closes = triple
        ? index + 1 < chars.length &&
            original[index - 1] == quote &&
            original[index] == quote &&
            original[index + 1] == quote
        : original[index - 1] == quote;
    if (!closes) continue;
    final closingLength = triple ? 3 : 1;
    for (var closeIndex = 0; closeIndex < closingLength - 1; closeIndex += 1) {
      if (chars[index] != '\n') {
        chars[index] = ' ';
      }
      index += 1;
    }
    return index;
  }
  return index;
}

AppColorsCheck checkAppColorsBaseline({
  required Directory repoRoot,
  required String baselineRelativePath,
  required String scanRootRelativePath,
}) {
  final baselineFile = File(
    _join(repoRoot.path, _normalize(baselineRelativePath)),
  );
  if (!baselineFile.existsSync()) {
    throw StateError('Missing AppColors baseline: $baselineRelativePath');
  }

  final baseline = int.parse(baselineFile.readAsStringSync().trim());
  final count = countPatternInDartFiles(
    Directory(_join(repoRoot.path, _normalize(scanRootRelativePath))),
    'AppColors.',
  );
  return AppColorsCheck(count: count, baseline: baseline);
}

int countPatternInDartFiles(Directory root, String pattern) {
  if (!root.existsSync()) return 0;
  var count = 0;
  final escaped = RegExp(RegExp.escape(pattern));
  for (final entity in root.listSync(recursive: true, followLinks: false)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    count += escaped.allMatches(entity.readAsStringSync()).length;
  }
  return count;
}

bool _isImportOrExportDirective(String line) {
  return line.startsWith('import ') || line.startsWith('export ');
}

String? _repoRootFromArgs(List<String> args) {
  final index = args.indexOf('--repo-root');
  if (index == -1) return null;
  if (index + 1 >= args.length) {
    throw ArgumentError('--repo-root requires a path');
  }
  return Directory(args[index + 1]).absolute.path;
}

String _normalize(String relativePath) {
  return relativePath.replaceAll('/', Platform.pathSeparator);
}

String _join(String first, String second) {
  if (first.endsWith(Platform.pathSeparator)) return '$first$second';
  return '$first${Platform.pathSeparator}$second';
}

String _relativeTo(String root, String path) {
  final normalizedRoot =
      root.replaceAll('\\', '/').replaceFirst(RegExp(r'/$'), '');
  final normalizedPath = path.replaceAll('\\', '/');
  return normalizedPath.startsWith('$normalizedRoot/')
      ? normalizedPath.substring(normalizedRoot.length + 1)
      : normalizedPath;
}

class GuardRule {
  const GuardRule({
    required this.name,
    required this.paths,
    required this.forbiddenImports,
  });

  final String name;
  final List<String> paths;
  final List<ForbiddenImport> forbiddenImports;
}

class ForbiddenImport {
  const ForbiddenImport(this.pattern, {required this.reason});

  final String pattern;
  final String reason;
}

class GuardIssue {
  const GuardIssue({
    required this.ruleName,
    required this.relativePath,
    required this.lineNumber,
    required this.directive,
    required this.forbiddenPattern,
    required this.reason,
  });

  final String ruleName;
  final String relativePath;
  final int lineNumber;
  final String directive;
  final String forbiddenPattern;
  final String reason;

  String format() {
    final location =
        lineNumber == 0 ? relativePath : '$relativePath:$lineNumber';
    return '$location [$ruleName] $reason '
        '(forbidden: $forbiddenPattern) -> $directive';
  }
}

class AppColorsCheck {
  const AppColorsCheck({required this.count, required this.baseline});

  final int count;
  final int baseline;

  bool get isPassing => count <= baseline;
}

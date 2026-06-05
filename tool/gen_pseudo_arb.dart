// Regenerate pseudo-locale ARB from English template:
//   dart run tool/gen_pseudo_arb.dart
//
// Reads app/lib/l10n/app_en.arb and writes app/lib/l10n/app_en_XA.arb.
// Then run code gen: cd app && flutter gen-l10n

import 'dart:convert';
import 'dart:io';

const _markerStart = '【';
const _markerEnd = '】';
const _padChar = '·';

const _accents = {
  'a': 'á',
  'e': 'é',
  'i': 'í',
  'o': 'ó',
  'u': 'ú',
  'A': 'Á',
  'E': 'É',
  'I': 'Í',
  'O': 'Ó',
  'U': 'Ú',
  'y': 'ý',
  'Y': 'Ý',
  'c': 'ç',
  'C': 'Ç',
};

final _placeholderPattern = RegExp(r'\{[^{}]+\}');

void main() {
  final input = File('app/lib/l10n/app_en.arb');
  final output = File('app/lib/l10n/app_en_XA.arb');
  if (!input.existsSync()) {
    stderr.writeln('Missing ${input.path} — run from repo root.');
    exit(1);
  }

  final decoded =
      jsonDecode(input.readAsStringSync()) as Map<String, dynamic>;
  final out = <String, dynamic>{};

  for (final entry in decoded.entries) {
    final key = entry.key;
    final value = entry.value;

    if (key == '@@locale') {
      out[key] = 'en_XA';
      continue;
    }

    if (key.startsWith('@')) {
      out[key] = value;
      continue;
    }

    if (value is String) {
      out[key] = pseudoize(value);
      continue;
    }

    out[key] = value;
  }

  output.writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(out)}\n');
  stdout.writeln('Wrote ${output.path}');
}

String pseudoize(String input) {
  if (input.isEmpty) return input;

  final accented = _accentPreservingPlaceholders(input);
  final padTotal = (accented.length * 0.35).round();
  final padLeft = padTotal ~/ 2;
  final padRight = padTotal - padLeft;
  return '$_markerStart${(_padChar * padLeft) + accented + (_padChar * padRight)}$_markerEnd';
}

String _accentPreservingPlaceholders(String input) {
  final buffer = StringBuffer();
  var lastEnd = 0;

  for (final match in _placeholderPattern.allMatches(input)) {
    buffer.write(_accentLetters(input.substring(lastEnd, match.start)));
    buffer.write(match.group(0));
    lastEnd = match.end;
  }

  buffer.write(_accentLetters(input.substring(lastEnd)));
  return buffer.toString();
}

String _accentLetters(String text) {
  final buffer = StringBuffer();
  for (final rune in text.runes) {
    final char = String.fromCharCode(rune);
    buffer.write(_accents[char] ?? char);
  }
  return buffer.toString();
}

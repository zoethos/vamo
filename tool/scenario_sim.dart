// Cycle 2 staging scenario simulator.
//
// Runs one multi-user hot-path flow against a non-prod Supabase project:
// sign in A/B, create trip, invite/join, add committed expense, propose/commit
// governance expense, amend FX conversion, and verify balances are readable.
//
// Required env:
//   SUPABASE_URL, SUPABASE_ANON_KEY
//   SCENARIO_USER_A_EMAIL / SCENARIO_USER_A_PASSWORD
//   SCENARIO_USER_B_EMAIL / SCENARIO_USER_B_PASSWORD
//
// Falls back to RLS_USER_A/B_* so the existing staging smoke users can run it.
// Set SCENARIO_TARGET_LABEL=staging or SCENARIO_ALLOW_NON_STAGING=true.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:supabase/supabase.dart';

Future<void> main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    stdout.writeln(_usage);
    return;
  }

  final label = _env('SCENARIO_TARGET_LABEL');
  if ((label == null || !label.toLowerCase().contains('staging')) &&
      _env('SCENARIO_ALLOW_NON_STAGING') != 'true') {
    stderr.writeln(
      'Refusing to run: set SCENARIO_TARGET_LABEL=staging for the staging '
      'project, or set SCENARIO_ALLOW_NON_STAGING=true only for another '
      'intentional non-prod target.',
    );
    exit(2);
  }

  final url = _required('SUPABASE_URL');
  if (url.contains(_knownProdSupabaseRef)) {
    stderr.writeln(
      'Refusing to run: SUPABASE_URL contains the known production project '
      'ref. Scenario runs write trips and expenses; use staging instead.',
    );
    exit(2);
  }
  final anon = _required('SUPABASE_ANON_KEY');
  final aEmail =
      _required('SCENARIO_USER_A_EMAIL', fallback: 'RLS_USER_A_EMAIL');
  final aPass = _required(
    'SCENARIO_USER_A_PASSWORD',
    fallback: 'RLS_USER_A_PASSWORD',
  );
  final bEmail =
      _required('SCENARIO_USER_B_EMAIL', fallback: 'RLS_USER_B_EMAIL');
  final bPass = _required(
    'SCENARIO_USER_B_PASSWORD',
    fallback: 'RLS_USER_B_PASSWORD',
  );

  final runId = DateTime.now()
      .toUtc()
      .toIso8601String()
      .replaceAll(RegExp(r'[^0-9A-Z]'), '')
      .toLowerCase();
  final stopwatch = Stopwatch()..start();
  final checks = <_Check>[];

  late final SupabaseClient clientA;
  late final SupabaseClient clientB;
  late final String userA;
  late final String userB;
  late final String tripId;
  late final String token;
  late final String committedExpenseId;
  late final String proposedExpenseId;

  try {
    clientA = await _step(
      'sign in A',
      checks,
      () => _signIn(url, anon, aEmail, aPass),
    );
    userA = clientA.auth.currentUser!.id;

    clientB = await _step(
      'sign in B',
      checks,
      () => _signIn(url, anon, bEmail, bPass),
    );
    userB = clientB.auth.currentUser!.id;

    tripId = _uuid();
    await _step('A create_trip', checks, () {
      return clientA.rpc('create_trip', params: {
        'p_id': tripId,
        'p_name': 'C2 scenario $runId',
        'p_destination': 'Staging',
        'p_start_date': DateTime.now().toUtc().toIso8601String().substring(
              0,
              10,
            ),
        'p_base_currency': 'EUR',
      });
    });

    final invite = await _step('A create invite', checks, () {
      return clientA
          .from('invites')
          .insert({'trip_id': tripId, 'created_by': userA})
          .select('token')
          .single();
    });
    token = invite['token'] as String;

    final joined = await _step('B join_trip', checks, () {
      return clientB.rpc('join_trip', params: {'p_token': token});
    });
    checks.add(_Check('B joined expected trip', joined == tripId));

    committedExpenseId = _uuid();
    await _step('A insert committed expense', checks, () {
      return clientA.rpc('insert_committed_expense', params: {
        'p_id': committedExpenseId,
        'p_trip_id': tripId,
        'p_payer_id': userA,
        'p_amount_cents': 1200,
        'p_currency': 'EUR',
        'p_base_cents': 1200,
        'p_fx_rate': 1,
        'p_description': 'C2 committed $runId',
        'p_category': 'food',
        'p_shares': <Map<String, dynamic>>[],
      });
    });

    proposedExpenseId = _uuid();
    await _step('B propose expense', checks, () {
      return clientB.rpc('propose_expense', params: {
        'p_id': proposedExpenseId,
        'p_trip_id': tripId,
        'p_payer_id': userB,
        'p_amount_cents': 900,
        'p_currency': 'EUR',
        'p_base_cents': 900,
        'p_fx_rate': 1,
        'p_description': 'C2 proposed $runId',
        'p_category': 'transport',
      });
    });

    await _step('A commit proposed expense', checks, () {
      return clientA.rpc('commit_expense', params: {
        'p_expense_id': proposedExpenseId,
      });
    });

    await _step('A amend FX conversion', checks, () {
      return clientA.rpc('amend_expense_conversion', params: {
        'p_expense_id': committedExpenseId,
        'p_base_cents': 1500,
        'p_fx_rate': 1.25,
        'p_fx_rate_source': 'manual',
        'p_fx_rate_manual': 1.25,
        'p_fx_conversion_locked': true,
      });
    });

    final expenses = await _step('B can read expenses', checks, () {
      return clientB
          .from('expenses')
          .select('id,status,base_cents,fx_conversion_locked')
          .eq('trip_id', tripId)
          .order('created_at');
    });
    final expenseRows = (expenses as List).cast<Map<String, dynamic>>();
    checks.add(_Check('B sees 2 expenses', expenseRows.length == 2));
    checks.add(
      _Check(
        'manual FX lock visible',
        expenseRows.any(
          (row) =>
              row['id'] == committedExpenseId &&
              row['fx_conversion_locked'] == true,
        ),
      ),
    );

    final members = await _step('A can read members', checks, () {
      return clientA
          .from('trip_members')
          .select('user_id,status')
          .eq('trip_id', tripId)
          .eq('status', 'active');
    });
    checks.add(
        _Check('trip has 2 active members', (members as List).length == 2));

    final balances = await _step('A can read balances', checks, () {
      return clientA
          .from('trip_balances')
          .select('user_id,net_cents')
          .eq('trip_id', tripId);
    });
    checks.add(_Check('balance rows present', (balances as List).length == 2));
    checks.add(
      _Check(
        'balance sum zero',
        balances.fold<int>(
              0,
              (sum, row) => sum + ((row as Map)['net_cents'] as int),
            ) ==
            0,
      ),
    );

    final failed = checks.where((c) => !c.pass).toList();
    final summary = {
      'ok': failed.isEmpty,
      'run_id': runId,
      'trip_id': tripId,
      'user_a': userA,
      'user_b': userB,
      'checks': checks.length,
      'failed': failed.map((c) => c.name).toList(),
      'elapsed_ms': stopwatch.elapsedMilliseconds,
    };
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(summary));
    exit(failed.isEmpty ? 0 : 1);
  } catch (error, stackTrace) {
    stderr.writeln('Scenario failed: $error');
    stderr.writeln(stackTrace);
    final summary = {
      'ok': false,
      'run_id': runId,
      'checks': checks.map((c) => {'name': c.name, 'pass': c.pass}).toList(),
      'elapsed_ms': stopwatch.elapsedMilliseconds,
    };
    stderr.writeln(const JsonEncoder.withIndent('  ').convert(summary));
    exit(1);
  }
}

Future<T> _step<T>(
  String name,
  List<_Check> checks,
  Future<T> Function() run,
) async {
  final watch = Stopwatch()..start();
  try {
    final result = await run();
    checks.add(_Check(name, true, detail: '${watch.elapsedMilliseconds}ms'));
    return result;
  } catch (error) {
    checks.add(_Check(name, false, detail: error.toString()));
    rethrow;
  }
}

Future<SupabaseClient> _signIn(
  String url,
  String anon,
  String email,
  String password,
) async {
  final client = SupabaseClient(url, anon);
  final response = await client.auth.signInWithPassword(
    email: email,
    password: password,
  );
  if (response.user == null) {
    throw StateError('sign-in returned no user for $email');
  }
  return client;
}

String _required(String key, {String? fallback}) {
  final value = _env(key, fallback: fallback);
  if (value == null || value.isEmpty) {
    final suffix = fallback == null ? '' : ' or $fallback';
    stderr.writeln('Missing env: $key$suffix');
    exit(2);
  }
  return value;
}

String? _env(String key, {String? fallback}) {
  final value = Platform.environment[key];
  if (value != null && value.isNotEmpty) return value;
  if (fallback == null) return null;
  final fallbackValue = Platform.environment[fallback];
  return fallbackValue != null && fallbackValue.isNotEmpty
      ? fallbackValue
      : null;
}

String _uuid() {
  final rand = Random.secure();
  final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  String hex(int b) => b.toRadixString(16).padLeft(2, '0');
  final h = bytes.map(hex).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20, 32)}';
}

class _Check {
  const _Check(this.name, this.pass, {this.detail});

  final String name;
  final bool pass;
  final String? detail;
}

const _usage = '''
Usage:
  dart run tool/scenario_sim.dart

Required env:
  SUPABASE_URL
  SUPABASE_ANON_KEY
  SCENARIO_USER_A_EMAIL / SCENARIO_USER_A_PASSWORD
  SCENARIO_USER_B_EMAIL / SCENARIO_USER_B_PASSWORD

Fallback env:
  RLS_USER_A_EMAIL / RLS_USER_A_PASSWORD
  RLS_USER_B_EMAIL / RLS_USER_B_PASSWORD

Safety:
  Set SCENARIO_TARGET_LABEL=staging. For a deliberate non-prod target with
  another label, set SCENARIO_ALLOW_NON_STAGING=true.

Output:
  JSON summary with run_id and trip_id. The trip is intentionally left in
  staging for dashboard inspection and manual cleanup.
''';

const _knownProdSupabaseRef = 'mjercplkmuoctdklosyy';

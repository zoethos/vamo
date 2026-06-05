// Executable RLS + storage policy smoke test against the cloud Supabase project.
//
// Prerequisites (create once in Supabase Auth dashboard — password users):
//   RLS_USER_A_EMAIL / RLS_USER_A_PASSWORD — trip owner
//   RLS_USER_B_EMAIL / RLS_USER_B_PASSWORD — joins via invite
//   RLS_USER_C_EMAIL / RLS_USER_C_PASSWORD — outsider (never joins)
//
// Also required:
//   SUPABASE_URL, SUPABASE_ANON_KEY
//
// Run from repo root (after `dart pub get`):
//   dart run tool/rls_smoke.dart
//
// Creates a throwaway trip, verifies member/outsider access, then cleans up
// storage objects. Trip row delete may require dashboard cleanup if no delete
// policy exists.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:supabase/supabase.dart';

/// Must stay aligned with [StoragePaths.expenseReceipt] in app_core.
String expenseReceiptPath({
  required String userId,
  required String tripId,
  required String expenseId,
  String ext = '.png',
}) =>
    '$userId/$tripId/receipts/$expenseId$ext';

const _capturesBucket = 'captures';

final _pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

Future<void> main() async {
  final url = Platform.environment['SUPABASE_URL'];
  final anon = Platform.environment['SUPABASE_ANON_KEY'];
  final aEmail = Platform.environment['RLS_USER_A_EMAIL'];
  final aPass = Platform.environment['RLS_USER_A_PASSWORD'];
  final bEmail = Platform.environment['RLS_USER_B_EMAIL'];
  final bPass = Platform.environment['RLS_USER_B_PASSWORD'];
  final cEmail = Platform.environment['RLS_USER_C_EMAIL'];
  final cPass = Platform.environment['RLS_USER_C_PASSWORD'];

  if ([url, anon, aEmail, aPass, bEmail, bPass, cEmail, cPass]
      .any((v) => v == null || v!.isEmpty)) {
    stderr.writeln(
      'Missing env. Set SUPABASE_URL, SUPABASE_ANON_KEY, '
      'RLS_USER_A/B/C_EMAIL and RLS_USER_A/B/C_PASSWORD.',
    );
    exit(2);
  }

  final results = <_Check>[];
  String? tripId;
  String? storagePath;
  String? bStoragePath;
  SupabaseClient? clientA;

  try {
    clientA = await _signIn(url!, anon!, aEmail!, aPass!);
    final userA = clientA.auth.currentUser!.id;
    final clientB = await _signIn(url, anon, bEmail!, bPass!);
    final clientC = await _signIn(url, anon, cEmail!, cPass!);

    tripId = _uuid();
    await clientA.rpc('create_trip', params: {
      'p_id': tripId,
      'p_name': 'RLS smoke ${DateTime.now().toUtc().toIso8601String()}',
    });
    results.add(_Check('A create_trip', true));

    final invite = await clientA
        .from('invites')
        .insert({'trip_id': tripId, 'created_by': userA})
        .select('token')
        .single();
    final token = invite['token'] as String;
    results.add(_Check('A create invite', true));

    final joinedTrip = await clientB.rpc('join_trip', params: {'p_token': token});
    results.add(_Check('B join_trip', joinedTrip == tripId));

    final placeId = _uuid();
    await clientA.from('places').insert({
      'id': placeId,
      'trip_id': tripId,
      'label': 'RLS smoke cafe',
      'source': 'receipt',
      'confidence': 0.6,
      'created_by': userA,
    });
    results.add(_Check('A insert place', true));

    final cPlaces =
        await clientC.from('places').select('id').eq('trip_id', tripId);
    results.add(_Check('C zero places rows', (cPlaces as List).isEmpty));

    final bPlaces =
        await clientB.from('places').select('id').eq('trip_id', tripId);
    results.add(_Check('B reads trip places', (bPlaces as List).length == 1));

    final expenseId = _uuid();
    storagePath = expenseReceiptPath(
      userId: userA,
      tripId: tripId,
      expenseId: expenseId,
    );
    await clientA.storage.from(_capturesBucket).uploadBinary(
          storagePath,
          _pngBytes,
          fileOptions: const FileOptions(contentType: 'image/png', upsert: true),
        );
    results.add(_Check('A upload receipt (4-segment path)', true));

    final bSigned =
        await clientB.storage.from(_capturesBucket).createSignedUrl(storagePath, 60);
    final bFetch = await http.get(Uri.parse(bSigned));
    results.add(_Check(
      'B member signed URL + fetch',
      bFetch.statusCode == 200,
    ));

    final userB = clientB.auth.currentUser!.id;
    final bExpenseId = _uuid();
    bStoragePath = expenseReceiptPath(
      userId: userB,
      tripId: tripId,
      expenseId: bExpenseId,
    );
    await clientB.storage.from(_capturesBucket).uploadBinary(
          bStoragePath,
          _pngBytes,
          fileOptions: const FileOptions(contentType: 'image/png', upsert: true),
        );
    results.add(_Check('B member upload (upsert)', true));

    await clientA
        .from('trip_members')
        .update({'status': 'left'})
        .eq('trip_id', tripId)
        .eq('user_id', userB);
    final bMemberAfterRemoval = await clientA
        .from('trip_members')
        .select('status')
        .eq('trip_id', tripId)
        .eq('user_id', userB)
        .single();
    results.add(_Check(
      'A removes B from trip (status left)',
      bMemberAfterRemoval['status'] == 'left',
    ));

    var bUpsertBlocked = false;
    try {
      await clientB.storage.from(_capturesBucket).uploadBinary(
            bStoragePath,
            _pngBytes,
            fileOptions: const FileOptions(contentType: 'image/png', upsert: true),
          );
    } catch (_) {
      bUpsertBlocked = true;
    }
    results.add(_Check('B ex-member upsert blocked', bUpsertBlocked));

    // Storage remove() is silent on RLS deny — verify object survival, not throws.
    List<FileObject> bRemoveResult = [];
    try {
      bRemoveResult =
          await clientB.storage.from(_capturesBucket).remove([bStoragePath]);
    } catch (_) {}
    final bActuallyRemoved =
        bRemoveResult.any((f) => f.name == bStoragePath);
    results.add(_Check(
      'B ex-member delete no-op (not in removed list)',
      !bActuallyRemoved,
    ));

    final aSignedAfterBDelete =
        await clientA.storage.from(_capturesBucket).createSignedUrl(bStoragePath, 60);
    final aFetchAfterBDelete = await http.get(Uri.parse(aSignedAfterBDelete));
    results.add(_Check(
      'B object survived ex-member delete',
      aFetchAfterBDelete.statusCode == 200,
    ));

    var cBlocked = false;
    try {
      await clientC.storage.from(_capturesBucket).createSignedUrl(storagePath, 60);
    } catch (_) {
      cBlocked = true;
    }
    results.add(_Check('C outsider cannot sign receipt URL', cBlocked));

    final cTrips = await clientC.from('trips').select('id').eq('id', tripId);
    results.add(_Check('C zero trip rows', (cTrips as List).isEmpty));

    final cBalances =
        await clientC.from('trip_balances').select('trip_id').eq('trip_id', tripId);
    results.add(_Check('C zero trip_balances rows', (cBalances as List).isEmpty));

    final cExpenses =
        await clientC.from('expenses').select('id').eq('trip_id', tripId);
    results.add(_Check('C zero expense rows', (cExpenses as List).isEmpty));

    var memberInsertBlocked = false;
    try {
      await clientC.from('trip_members').insert({
        'trip_id': tripId,
        'user_id': clientC.auth.currentUser!.id,
        'role': 'member',
        'status': 'active',
      });
    } catch (_) {
      memberInsertBlocked = true;
    }
    results.add(_Check('C cannot self-insert trip_members', memberInsertBlocked));

    await clientA.from('suggestions').insert({
      'user_id': userA,
      'body': 'rls_smoke_${tripId}_suggestion',
      'category': 'other',
    });
    final bSuggestions = await clientB
        .from('suggestions')
        .select('id')
        .eq('body', 'rls_smoke_${tripId}_suggestion');
    results.add(_Check('B cannot read A suggestions', (bSuggestions as List).isEmpty));
  } catch (e, st) {
    stderr.writeln('Unexpected error: $e\n$st');
    results.add(_Check('unexpected error', false, detail: '$e'));
  } finally {
    if (clientA != null) {
      for (final path in [storagePath, bStoragePath]) {
        if (path == null) continue;
        try {
          await clientA.storage.from(_capturesBucket).remove([path]);
          results.add(_Check('cleanup storage $path', true));
        } catch (e) {
          results.add(_Check('cleanup storage $path', false, detail: '$e'));
        }
      }
    }
    if (clientA != null && tripId != null) {
      try {
        await clientA.from('trips').delete().eq('id', tripId);
        results.add(_Check('cleanup trip delete', true));
      } catch (e) {
        results.add(_Check(
          'cleanup trip delete',
          false,
          detail: '$e (delete manually in dashboard if needed)',
        ));
      }
    }
  }

  stdout.writeln('\nRLS smoke results');
  stdout.writeln('${'Check'.padRight(40)} Result');
  stdout.writeln('${'-' * 40} ------');
  var failed = 0;
  for (final row in results) {
    stdout.writeln('${row.name.padRight(40)} ${row.pass ? 'PASS' : 'FAIL'}');
    if (!row.pass) {
      failed++;
      if (row.detail != null) stderr.writeln('  ↳ ${row.detail}');
    }
  }
  stdout.writeln('\n${results.length - failed}/${results.length} passed');
  exit(failed == 0 ? 0 : 1);
}

Future<SupabaseClient> _signIn(
  String url,
  String anonKey,
  String email,
  String password,
) async {
  final client = SupabaseClient(url, anonKey);
  await client.auth.signInWithPassword(email: email, password: password);
  if (client.auth.currentSession == null) {
    throw StateError('Sign-in failed for $email');
  }
  return client;
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
  _Check(this.name, this.pass, {this.detail});
  final String name;
  final bool pass;
  final String? detail;
}

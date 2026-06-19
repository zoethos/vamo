// Executable RLS + storage policy smoke test against the cloud Supabase project.
//
// Prerequisites (create once in Supabase Auth dashboard — password users):
//   RLS_USER_A_EMAIL / RLS_USER_A_PASSWORD — trip owner
//   RLS_USER_B_EMAIL / RLS_USER_B_PASSWORD — joins via invite
//   RLS_USER_C_EMAIL / RLS_USER_C_PASSWORD — outsider (never joins)
//   RLS_SERVICE_ROLE_KEY — lifecycle job + deterministic service-role writers
//     for tests that must not hit external providers repeatedly
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
const _avatarsBucket = 'avatars';

final _pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

const _s23SmokeTheme = {
  'id': 'rls-smoke',
  'label': 'Smoke',
  'gradient': ['#102033', '#24364F', '#4C2E4D'],
  'statBackground': '#F6F7FB',
  'statPrimary': '#111827',
  'statMuted': '#374151',
  'accent': '#FF5B4D',
  'memberBubble': '#F6F7FB',
  'memberInitial': '#111827',
  'tagline': 'Si va?',
};

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
      .any((v) => v == null || v.isEmpty)) {
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
  String? aAvatarPath;
  String? bAvatarPath;
  SupabaseClient? clientA;
  SupabaseClient? clientB;
  SupabaseClient? serviceClient;

  try {
    clientA = await _signIn(url!, anon!, aEmail!, aPass!);
    final userA = clientA.auth.currentUser!.id;
    clientB = await _signIn(url, anon, bEmail!, bPass!);
    final clientC = await _signIn(url, anon, cEmail!, cPass!);
    final serviceKey = Platform.environment['RLS_SERVICE_ROLE_KEY'];
    serviceClient = serviceKey != null && serviceKey.isNotEmpty
        ? SupabaseClient(url, serviceKey)
        : null;

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

    // --- S25 share preview (anon RPC; no direct table reads) ---
    final anonPreviewClient = SupabaseClient(url, anon);
    final preview = await anonPreviewClient
        .rpc('get_trip_preview', params: {'p_token': token});
    results.add(_Check('S25 get_trip_preview valid token', preview != null));
    if (preview != null) {
      final map = Map<String, dynamic>.from(preview as Map);
      results.add(_Check('S25 preview trip_name', map['trip_name'] != null));
      results
          .add(_Check('S25 preview member_count', map['member_count'] != null));
      results.add(_Check('S25 preview theme pack', map['theme'] != null));
      results.add(_Check(
        'S25 preview no financial fields',
        !map.containsKey('amount_cents') &&
            !map.containsKey('balances') &&
            !map.containsKey('net_cents'),
      ));
      results.add(_Check(
        'S25 preview no member roster',
        !map.containsKey('members') && !map.containsKey('member_names'),
      ));
      results.add(_Check(
        'S25 preview no capture metadata',
        !map.containsKey('captured_lat') &&
            !map.containsKey('captured_lng') &&
            !map.containsKey('media_captured_at') &&
            !map.containsKey('photos'),
      ));
    }
    final badPreview = await anonPreviewClient
        .rpc('get_trip_preview', params: {'p_token': 'invalid-token-xyz'});
    results.add(
        _Check('S25 get_trip_preview invalid token null', badPreview == null));
    results.add(_Check(
      'S23 anon cannot read destination_themes',
      await _selectDeniedOrEmpty(anonPreviewClient, 'destination_themes'),
    ));
    results.add(_Check(
      'S23 anon cannot read destination_theme_aliases',
      await _selectDeniedOrEmpty(
          anonPreviewClient, 'destination_theme_aliases'),
    ));
    final anonInviteRows =
        await anonPreviewClient.from('invites').select('token').limit(1);
    results.add(_Check(
      'S25 anon cannot read invites table',
      (anonInviteRows as List).isEmpty,
    ));
    if (serviceClient != null) {
      final exhaustInvite = await clientA
          .from('invites')
          .insert({'trip_id': tripId, 'created_by': userA})
          .select('token, max_uses')
          .single();
      await serviceClient.from('invites').update({
        'uses': exhaustInvite['max_uses'],
      }).eq('token', exhaustInvite['token'] as String);
      final exhaustedPreview = await anonPreviewClient.rpc('get_trip_preview',
          params: {'p_token': exhaustInvite['token'] as String});
      results.add(_Check(
          'S25 get_trip_preview exhausted null', exhaustedPreview == null));
    }

    var directThemeUpdateBlocked = false;
    try {
      await clientA
          .from('trips')
          .update({'theme': _s23SmokeTheme}).eq('id', tripId);
    } catch (_) {
      directThemeUpdateBlocked = true;
    }
    final directThemeRow =
        await clientA.from('trips').select('theme').eq('id', tripId).single();
    results.add(_Check(
      'S23 direct trip theme update blocked',
      directThemeUpdateBlocked || directThemeRow['theme'] == null,
    ));

    if (serviceClient != null) {
      await serviceClient.rpc('_apply_trip_theme', params: {
        'p_trip_id': tripId,
        'p_theme': _s23SmokeTheme,
      });
      final themedPreview = await anonPreviewClient
          .rpc('get_trip_preview', params: {'p_token': token});
      final themedMap = Map<String, dynamic>.from(themedPreview as Map);
      final theme = Map<String, dynamic>.from(themedMap['theme'] as Map);
      results.add(_Check(
        'S23 service theme visible through preview',
        theme['id'] == 'rls-smoke',
      ));
    } else {
      results.add(_Check(
        'S23 service theme apply skipped',
        false,
        detail: 'set RLS_SERVICE_ROLE_KEY for _apply_trip_theme smoke',
      ));
    }

    final joinedTrip =
        await clientB.rpc('join_trip', params: {'p_token': token});
    results.add(_Check('B join_trip', joinedTrip == tripId));

    final userB = clientB.auth.currentUser!.id;

    // --- S47 profile avatars (display_name privacy tier) ---
    aAvatarPath = '$userA/profile.jpg';
    bAvatarPath = '$userB/profile.jpg';
    const avatarUploadOptions = FileOptions(
      contentType: 'image/jpeg',
      upsert: true,
    );
    await clientA.storage.from(_avatarsBucket).uploadBinary(
          aAvatarPath,
          _pngBytes,
          fileOptions: avatarUploadOptions,
        );
    results.add(_Check('S47 A avatar insert own path', true));
    await clientA.storage.from(_avatarsBucket).uploadBinary(
          aAvatarPath,
          _pngBytes,
          fileOptions: avatarUploadOptions,
        );
    results.add(_Check('S47 A avatar upsert own path', true));
    final aAvatarSigned = await clientA.storage
        .from(_avatarsBucket)
        .createSignedUrl(aAvatarPath, 60);
    results.add(_Check(
      'S47 A avatar select own path',
      aAvatarSigned.isNotEmpty,
    ));
    final bReadAvatar = await clientB.storage
        .from(_avatarsBucket)
        .createSignedUrl(aAvatarPath, 60);
    results.add(_Check(
      'S47 B can select A avatar (display_name tier)',
      bReadAvatar.isNotEmpty,
    ));
    var bWriteAvatarBlocked = false;
    try {
      await clientB.storage.from(_avatarsBucket).uploadBinary(
            aAvatarPath,
            _pngBytes,
            fileOptions: avatarUploadOptions,
          );
    } catch (_) {
      bWriteAvatarBlocked = true;
    }
    results.add(
        _Check('S47 B blocked writing A avatar path', bWriteAvatarBlocked));
    var aWriteBAvatarBlocked = false;
    try {
      await clientA.storage.from(_avatarsBucket).uploadBinary(
            bAvatarPath,
            _pngBytes,
            fileOptions: avatarUploadOptions,
          );
    } catch (_) {
      aWriteBAvatarBlocked = true;
    }
    results.add(
        _Check('S47 A blocked writing B avatar path', aWriteBAvatarBlocked));

    var aSetBAvatarUrlBlocked = false;
    try {
      await clientA
          .from('profiles')
          .update({'avatar_url': bAvatarPath}).eq('id', userA);
    } catch (_) {
      aSetBAvatarUrlBlocked = true;
    }
    results.add(_Check(
      'S47 A blocked setting avatar_url to B path',
      aSetBAvatarUrlBlocked,
    ));

    var aSetOwnAvatarUrlOk = false;
    try {
      await clientA
          .from('profiles')
          .update({'avatar_url': aAvatarPath}).eq('id', userA);
      aSetOwnAvatarUrlOk = true;
    } catch (_) {}
    results
        .add(_Check('S47 A can set own avatar_url path', aSetOwnAvatarUrlOk));

    var aSetNullAvatarUrlOk = false;
    try {
      await clientA
          .from('profiles')
          .update({'avatar_url': null}).eq('id', userA);
      aSetNullAvatarUrlOk = true;
    } catch (_) {}
    results
        .add(_Check('S47 A can clear avatar_url to null', aSetNullAvatarUrlOk));

    var aDeleteOwnAvatarOk = false;
    try {
      await clientA.storage.from(_avatarsBucket).remove([aAvatarPath]);
      aDeleteOwnAvatarOk = true;
    } catch (_) {}
    results
        .add(_Check('S47 A can delete own avatar object', aDeleteOwnAvatarOk));

    await clientB.storage.from(_avatarsBucket).uploadBinary(
          bAvatarPath,
          _pngBytes,
          fileOptions: avatarUploadOptions,
        );
    // Storage remove() is silent on RLS deny — verify object survival, not throws.
    List<FileObject> aRemoveBResult = [];
    try {
      aRemoveBResult =
          await clientA.storage.from(_avatarsBucket).remove([bAvatarPath]);
    } catch (_) {}
    final bAvatarActuallyRemoved =
        aRemoveBResult.any((f) => f.name == bAvatarPath);
    final bAvatarSignedAfterCrossDelete = await clientB.storage
        .from(_avatarsBucket)
        .createSignedUrl(bAvatarPath, 60);
    final bAvatarFetchAfterCrossDelete =
        await http.get(Uri.parse(bAvatarSignedAfterCrossDelete));
    results.add(_Check(
      'S47 A blocked deleting B avatar object',
      !bAvatarActuallyRemoved && bAvatarFetchAfterCrossDelete.statusCode == 200,
    ));

    // --- S19 money governance (R5) — two members, before role promotion ---
    final netBaseline = await _netCents(clientB, tripId, userB);
    final proposedId = _uuid();
    await clientA.rpc('propose_expense', params: {
      'p_id': proposedId,
      'p_trip_id': tripId,
      'p_payer_id': userA,
      'p_amount_cents': 2000,
      'p_currency': 'EUR',
      'p_base_cents': 2000,
      'p_fx_rate': 1,
      'p_description': 'RLS proposed dinner',
    });
    final netDuringProposed = await _netCents(clientB, tripId, userB);
    results.add(_Check(
      'proposed expense leaves net_cents unchanged',
      netDuringProposed == netBaseline,
    ));

    var memberCommitBlocked = false;
    try {
      await clientB.rpc('commit_expense', params: {'p_expense_id': proposedId});
    } catch (_) {
      memberCommitBlocked = true;
    }
    results.add(
        _Check('member cannot commit proposed expense', memberCommitBlocked));

    await clientA.rpc('commit_expense', params: {'p_expense_id': proposedId});
    final netAfterCommit = await _netCents(clientB, tripId, userB);
    results.add(_Check(
      'commit changes net_cents',
      netAfterCommit != netBaseline,
    ));

    final bornCommittedId = _uuid();
    await clientB.from('expenses').insert({
      'id': bornCommittedId,
      'trip_id': tripId,
      'payer_id': userB,
      'amount_cents': 1000,
      'currency': 'EUR',
      'base_cents': 1000,
      'fx_rate': 1,
      'description': 'born committed',
      'created_by': userB,
    });
    await clientB.from('expense_shares').insert([
      {
        'id': _uuid(),
        'expense_id': bornCommittedId,
        'user_id': userA,
        'share_cents': 500,
      },
      {
        'id': _uuid(),
        'expense_id': bornCommittedId,
        'user_id': userB,
        'share_cents': 500,
      },
    ]);
    final bornShares = await clientA
        .from('expense_shares')
        .select('response')
        .eq('expense_id', bornCommittedId);
    results.add(_Check(
      'born-committed shares default accepted',
      (bornShares as List).every((r) => r['response'] == 'accepted'),
    ));

    var forgedRejectedInsertBlocked = false;
    final forgedExpenseId = _uuid();
    await clientA.from('expenses').insert({
      'id': forgedExpenseId,
      'trip_id': tripId,
      'payer_id': userA,
      'amount_cents': 1000,
      'currency': 'EUR',
      'base_cents': 1000,
      'fx_rate': 1,
      'description': 'forged guard smoke',
      'created_by': userA,
    });
    await clientA.from('expense_shares').insert({
      'id': _uuid(),
      'expense_id': forgedExpenseId,
      'user_id': userA,
      'share_cents': 500,
    });
    try {
      await clientB.from('expense_shares').insert({
        'id': _uuid(),
        'expense_id': forgedExpenseId,
        'user_id': userB,
        'share_cents': 500,
        'response': 'rejected',
        'response_reason': 'forged dispute',
        'responded_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (_) {
      forgedRejectedInsertBlocked = true;
    }
    results.add(_Check(
      'forged rejected share insert blocked',
      forgedRejectedInsertBlocked,
    ));

    final netBeforeReject = await _netCents(clientB, tripId, userB);
    await clientB.rpc('respond_to_share', params: {
      'p_expense_id': bornCommittedId,
      'p_accept': false,
      'p_reason': 'rls smoke dispute',
    });
    final netAfterReject = await _netCents(clientB, tripId, userB);
    final shareRowsAfterDispute = await clientA
        .from('expense_shares')
        .select('user_id, response')
        .eq('expense_id', bornCommittedId);
    final bShareRow = (shareRowsAfterDispute as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((r) => r['user_id'] == userB);
    final aShareRow = (shareRowsAfterDispute as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((r) => r['user_id'] == userA);
    results.add(_Check(
      'respond_to_share updates caller share only',
      bShareRow['response'] == 'rejected' &&
          aShareRow['response'] == 'accepted',
    ));
    await clientB.rpc('respond_to_share', params: {
      'p_expense_id': bornCommittedId,
      'p_accept': true,
    });
    final netAfterAccept = await _netCents(clientB, tripId, userB);
    results.add(_Check(
      'reject vs accept on committed share → same net_cents',
      netAfterReject == netBeforeReject && netAfterAccept == netAfterReject,
    ));

    // void/cancelled net — isolated writable trip (main trip accumulates other expenses)
    final voidTripId = _uuid();
    await clientA.rpc('create_trip', params: {
      'p_id': voidTripId,
      'p_name': 'RLS void smoke',
    });
    final voidInvite = await clientA
        .from('invites')
        .insert({'trip_id': voidTripId, 'created_by': userA})
        .select('token')
        .single();
    await clientB
        .rpc('join_trip', params: {'p_token': voidInvite['token'] as String});
    final voidBaseline = await _netCents(clientB, voidTripId, userB);
    final voidExpenseId = _uuid();
    await clientA.rpc('propose_expense', params: {
      'p_id': voidExpenseId,
      'p_trip_id': voidTripId,
      'p_payer_id': userA,
      'p_amount_cents': 2000,
      'p_currency': 'EUR',
      'p_base_cents': 2000,
      'p_fx_rate': 1,
      'p_description': 'RLS void target',
    });
    await clientA
        .rpc('commit_expense', params: {'p_expense_id': voidExpenseId});
    final voidNetCommitted = await _netCents(clientB, voidTripId, userB);
    await clientA.rpc('void_expense', params: {'p_expense_id': voidExpenseId});
    final voidNetAfterVoid = await _netCents(clientB, voidTripId, userB);
    results.add(_Check(
      'void/cancelled expense leaves net_cents',
      voidNetCommitted != voidBaseline && voidNetAfterVoid == voidBaseline,
    ));

    // --- S20 budget + FX (R6) — member B before co-admin promotion ---
    var memberBudgetBlocked = false;
    try {
      await clientB.rpc('set_trip_budget', params: {
        'p_trip_id': tripId,
        'p_mode': 'formal',
        'p_cents': 50000,
      });
    } catch (_) {
      memberBudgetBlocked = true;
    }
    results.add(_Check('member cannot set budget', memberBudgetBlocked));

    await clientA.rpc('set_trip_budget', params: {
      'p_trip_id': tripId,
      'p_mode': 'formal',
      'p_cents': 50000,
    });
    final budgetRow = await clientA
        .from('trips')
        .select('budget_mode, budget_cents')
        .eq('id', tripId)
        .single();
    results.add(_Check(
      'admin sets formal budget',
      budgetRow['budget_mode'] == 'formal' &&
          budgetRow['budget_cents'] == 50000,
    ));

    var outsiderSpendBlocked = false;
    try {
      await clientC.rpc('trip_committed_spend_cents', params: {
        'p_trip_id': tripId,
      });
    } catch (_) {
      outsiderSpendBlocked = true;
    }
    results.add(_Check(
      'outsider cannot read committed spend helper',
      outsiderSpendBlocked,
    ));

    final fxExpenseId = _uuid();
    await clientA.from('expenses').insert({
      'id': fxExpenseId,
      'trip_id': tripId,
      'payer_id': userA,
      'amount_cents': 1000,
      'currency': 'EUR',
      'base_cents': 1000,
      'fx_rate': 1,
      'description': 'fx forward-only anchor',
      'created_by': userA,
    });
    final fxBefore = await clientA
        .from('expenses')
        .select('fx_rate')
        .eq('id', fxExpenseId)
        .single();
    final rateBefore = (fxBefore['fx_rate'] as num).toDouble();

    await clientA.rpc('capture_trip_fx_rate', params: {
      'p_trip_id': tripId,
      'p_currency': 'USD',
    });
    final fxRow = await clientA
        .from('trip_fx_rates')
        .select('currency, source, captured_by, rate')
        .eq('trip_id', tripId)
        .eq('currency', 'USD')
        .single();
    results.add(_Check(
      'captured FX row has source and captured_by',
      fxRow['source'] != null &&
          fxRow['captured_by'] == userA &&
          fxRow['rate'] != null,
    ));

    final firstRate = (fxRow['rate'] as num).toDouble();
    final simulatedRate = firstRate + 0.123456;
    if (serviceClient != null) {
      await serviceClient.rpc('_apply_trip_fx_rate', params: {
        'p_trip_id': tripId,
        'p_currency': 'USD',
        'p_rate': simulatedRate,
        'p_source': 'test',
        'p_captured_by': userA,
      });
    }
    final fxRows = await clientA
        .from('trip_fx_rates')
        .select('id, rate, source')
        .eq('trip_id', tripId)
        .eq('currency', 'USD');
    final fxRowList = (fxRows as List).cast<Map<String, dynamic>>();
    final refreshedRate =
        fxRowList.isEmpty ? 0.0 : (fxRowList.first['rate'] as num).toDouble();
    final fxAfter = await clientA
        .from('expenses')
        .select('fx_rate')
        .eq('id', fxExpenseId)
        .single();
    final rateAfter = (fxAfter['fx_rate'] as num).toDouble();
    results.add(_Check(
      'FX refresh overwrites trip row not expense snapshot',
      serviceClient != null &&
          fxRowList.length == 1 &&
          (refreshedRate - simulatedRate).abs() < 0.000001 &&
          fxRowList.first['source'] == 'test' &&
          rateAfter == rateBefore,
      detail: serviceClient == null
          ? 'set RLS_SERVICE_ROLE_KEY for deterministic FX refresh'
          : null,
    ));
    results.add(_Check(
      'FX refresh returns a rate row',
      firstRate > 0,
    ));

    final overBudgetId = _uuid();
    await clientA.rpc('propose_expense', params: {
      'p_id': overBudgetId,
      'p_trip_id': tripId,
      'p_payer_id': userA,
      'p_amount_cents': 60000,
      'p_currency': 'EUR',
      'p_base_cents': 60000,
      'p_fx_rate': 1,
      'p_description': 'over formal budget',
    });
    var overBudgetCommitFailed = false;
    try {
      await clientA
          .rpc('commit_expense', params: {'p_expense_id': overBudgetId});
    } catch (_) {
      overBudgetCommitFailed = true;
    }
    results.add(_Check(
      'formal over-budget commit succeeds at DB',
      !overBudgetCommitFailed,
    ));

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
          fileOptions:
              const FileOptions(contentType: 'image/png', upsert: true),
        );
    results.add(_Check('A upload receipt (4-segment path)', true));

    final bSigned = await clientB.storage
        .from(_capturesBucket)
        .createSignedUrl(storagePath, 60);
    final bFetch = await http.get(Uri.parse(bSigned));
    results.add(_Check(
      'B member signed URL + fetch',
      bFetch.statusCode == 200,
    ));

    final photoId = _uuid();
    await clientA.from('trip_photos').insert({
      'id': photoId,
      'trip_id': tripId,
      'storage_path': storagePath,
      'caption': 'metadata smoke',
      'captured_at': DateTime.now().toUtc().toIso8601String(),
      'captured_lat': 40.7128,
      'captured_lng': -74.0060,
      'media_captured_at': DateTime.utc(2026, 6, 1, 12).toIso8601String(),
      'created_by': userA,
    });
    final bPhotos = await clientB
        .from('trip_photos')
        .select('id, captured_lat, captured_lng, media_captured_at')
        .eq('id', photoId);
    final bPhoto = (bPhotos as List).isEmpty
        ? null
        : Map<String, dynamic>.from(bPhotos.first as Map);
    results.add(_Check(
      'B reads trip photo metadata',
      bPhoto?['captured_lat'] == 40.7128 &&
          bPhoto?['captured_lng'] == -74.0060 &&
          bPhoto?['media_captured_at'] != null,
    ));
    final cPhotos =
        await clientC.from('trip_photos').select('id').eq('id', photoId);
    results.add(
      _Check('C zero trip photo rows', (cPhotos as List).isEmpty),
    );

    final bExpenseId = _uuid();
    bStoragePath = expenseReceiptPath(
      userId: userB,
      tripId: tripId,
      expenseId: bExpenseId,
    );
    await clientB.storage.from(_capturesBucket).uploadBinary(
          bStoragePath,
          _pngBytes,
          fileOptions:
              const FileOptions(contentType: 'image/png', upsert: true),
        );
    results.add(_Check('B member upload (upsert)', true));

    // --- S16 role cases (R1) — before B is removed from trip ---
    await clientA
        .from('trips')
        .update({'destination': 'RLS baseline'}).eq('id', tripId);

    await clientB
        .from('trips')
        .update({'destination': 'Member edit'}).eq('id', tripId);
    final tripAfterMemberEdit = await clientB
        .from('trips')
        .select('destination')
        .eq('id', tripId)
        .single();
    results.add(_Check(
      'B member cannot update trip',
      tripAfterMemberEdit['destination'] == 'RLS baseline',
    ));

    await clientA.rpc('set_member_role', params: {
      'p_trip_id': tripId,
      'p_user_id': userB,
      'p_role': 'co-admin',
    });
    final bRole = await clientA
        .from('trip_members')
        .select('role')
        .eq('trip_id', tripId)
        .eq('user_id', userB)
        .single();
    results
        .add(_Check('A promotes B to co-admin', bRole['role'] == 'co-admin'));

    await clientB
        .from('trips')
        .update({'destination': 'Co-admin edit'}).eq('id', tripId);
    final tripAfterCoAdmin = await clientB
        .from('trips')
        .select('destination')
        .eq('id', tripId)
        .single();
    results.add(_Check(
      'B co-admin can update trip fields',
      tripAfterCoAdmin['destination'] == 'Co-admin edit',
    ));

    await clientB
        .from('trip_members')
        .update({'role': 'member'})
        .eq('trip_id', tripId)
        .eq('user_id', userA);
    final ownerRoleAfter = await clientA
        .from('trip_members')
        .select('role')
        .eq('trip_id', tripId)
        .eq('user_id', userA)
        .single();
    results.add(_Check(
      'B co-admin cannot change roles',
      ownerRoleAfter['role'] == 'owner',
    ));

    await clientA
        .from('trips')
        .update({'destination': 'RLS baseline'}).eq('id', tripId);

    // --- S18 TripBoard (R4) — before close ---
    final planItemId = _uuid();
    await clientB.from('trip_plan_items').insert({
      'id': planItemId,
      'trip_id': tripId,
      'kind': 'lodging',
      'title': 'RLS smoke hotel',
      'created_by': userB,
    });
    results.add(_Check('B insert plan item', true));

    var outsiderPlanBlocked = false;
    try {
      await clientC.from('trip_plan_items').insert({
        'id': _uuid(),
        'trip_id': tripId,
        'kind': 'other',
        'title': 'blocked',
        'created_by': clientC.auth.currentUser!.id,
      });
    } catch (_) {
      outsiderPlanBlocked = true;
    }
    results.add(_Check('C outsider plan insert blocked', outsiderPlanBlocked));

    final listItemId = _uuid();
    await clientB.from('trip_list_items').insert({
      'id': listItemId,
      'trip_id': tripId,
      'list_name': 'Packing',
      'label': 'sunscreen',
      'created_by': userB,
    });
    await clientB.from('trip_list_items').update({
      'checked_by': userB,
      'checked_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', listItemId);
    final checkedRow = await clientB
        .from('trip_list_items')
        .select('checked_by')
        .eq('id', listItemId)
        .single();
    results.add(_Check(
      'B checks list item (checked_by = B)',
      checkedRow['checked_by'] == userB,
    ));

    // --- S21 event RSVP (R8) — before close ---
    final eventActivityId = _uuid();
    await clientA.from('trip_plan_items').insert({
      'id': eventActivityId,
      'trip_id': tripId,
      'kind': 'activity',
      'title': 'RLS smoke dinner',
      'created_by': userA,
    });
    final eventActivitySeenByB = await clientB
        .from('trip_plan_items')
        .select('id, kind')
        .eq('id', eventActivityId)
        .maybeSingle();
    results.add(_Check(
      'B reads A activity event',
      eventActivitySeenByB?['id'] == eventActivityId &&
          eventActivitySeenByB?['kind'] == 'activity',
    ));

    await clientB.rpc('set_event_rsvp', params: {
      'p_plan_item_id': eventActivityId,
      'p_status': 'going',
    });
    final rsvpGoing = await clientB
        .from('trip_plan_item_rsvps')
        .select('status')
        .eq('plan_item_id', eventActivityId)
        .eq('user_id', userB)
        .maybeSingle();
    results.add(_Check(
      'B set own RSVP going',
      rsvpGoing?['status'] == 'going',
    ));
    final rsvpGoingSeenByA = await clientA
        .from('trip_plan_item_rsvps')
        .select('status')
        .eq('plan_item_id', eventActivityId)
        .eq('user_id', userB)
        .maybeSingle();
    results.add(_Check(
      'A reads B RSVP going',
      rsvpGoingSeenByA?['status'] == 'going',
    ));

    await clientB.rpc('set_event_rsvp', params: {
      'p_plan_item_id': eventActivityId,
      'p_status': 'maybe',
    });
    final rsvpRows = await clientB
        .from('trip_plan_item_rsvps')
        .select('status')
        .eq('plan_item_id', eventActivityId)
        .eq('user_id', userB);
    results.add(_Check(
      'B update RSVP (single row)',
      (rsvpRows as List).length == 1 &&
          (rsvpRows.first as Map)['status'] == 'maybe',
    ));

    var ownRowOnlyBlocked = false;
    try {
      await clientB.from('trip_plan_item_rsvps').insert({
        'plan_item_id': eventActivityId,
        'user_id': userA,
        'status': 'going',
      });
    } catch (_) {
      ownRowOnlyBlocked = true;
    }
    results.add(_Check('B cannot RSVP for another member', ownRowOnlyBlocked));

    var outsiderRsvpBlocked = false;
    try {
      await clientC.rpc('set_event_rsvp', params: {
        'p_plan_item_id': eventActivityId,
        'p_status': 'going',
      });
    } catch (_) {
      outsiderRsvpBlocked = true;
    }
    results.add(_Check('C outsider RSVP blocked', outsiderRsvpBlocked));

    final outsiderRsvpRows = await clientC
        .from('trip_plan_item_rsvps')
        .select('id')
        .eq('plan_item_id', eventActivityId);
    results.add(_Check(
      'C outsider cannot read RSVPs',
      (outsiderRsvpRows as List).isEmpty,
    ));

    var lodgingRsvpRejected = false;
    try {
      await clientB.rpc('set_event_rsvp', params: {
        'p_plan_item_id': planItemId,
        'p_status': 'going',
      });
    } catch (_) {
      lodgingRsvpRejected = true;
    }
    results.add(_Check('RSVP on lodging rejected', lodgingRsvpRejected));

    // --- S21 cascade delete — active RSVP rows must not block plan/trip delete ---
    final cascadeEventId = _uuid();
    await clientB.from('trip_plan_items').insert({
      'id': cascadeEventId,
      'trip_id': tripId,
      'kind': 'activity',
      'title': 'RLS cascade dinner',
      'created_by': userB,
    });
    await clientB.rpc('set_event_rsvp', params: {
      'p_plan_item_id': cascadeEventId,
      'p_status': 'going',
    });
    final rsvpBeforeCascade = await clientB
        .from('trip_plan_item_rsvps')
        .select('id')
        .eq('plan_item_id', cascadeEventId);
    var planDeleteWithRsvpOk = false;
    try {
      await clientA.from('trip_plan_items').delete().eq('id', cascadeEventId);
      planDeleteWithRsvpOk = true;
    } catch (_) {}
    final planAfterCascadeDelete = await clientA
        .from('trip_plan_items')
        .select('id')
        .eq('id', cascadeEventId)
        .maybeSingle();
    final rsvpsAfterPlanDelete = await clientA
        .from('trip_plan_item_rsvps')
        .select('id')
        .eq('plan_item_id', cascadeEventId);
    results.add(_Check(
      'delete activity with active RSVP cascades',
      (rsvpBeforeCascade as List).isNotEmpty &&
          planDeleteWithRsvpOk &&
          planAfterCascadeDelete == null &&
          (rsvpsAfterPlanDelete as List).isEmpty,
    ));

    final cascadeTripId = _uuid();
    await clientA.rpc('create_trip', params: {
      'p_id': cascadeTripId,
      'p_name': 'RLS cascade trip',
      'p_start_date': DateTime.now()
          .toUtc()
          .add(const Duration(days: 14))
          .toIso8601String()
          .substring(0, 10),
    });
    final cascadeTripEventId = _uuid();
    await clientA.from('trip_plan_items').insert({
      'id': cascadeTripEventId,
      'trip_id': cascadeTripId,
      'kind': 'activity',
      'title': 'Cascade trip event',
      'created_by': userA,
    });
    await clientA.rpc('set_event_rsvp', params: {
      'p_plan_item_id': cascadeTripEventId,
      'p_status': 'maybe',
    });
    final cascadeTripRsvpBefore = await clientA
        .from('trip_plan_item_rsvps')
        .select('id')
        .eq('plan_item_id', cascadeTripEventId);

    // 0001 trips policy: read/insert/update only — users cancel, never hard-delete.
    try {
      await clientA.from('trips').delete().eq('id', cascadeTripId);
    } catch (_) {}
    final cascadeTripAfterUserDelete = await clientA
        .from('trips')
        .select('id')
        .eq('id', cascadeTripId)
        .maybeSingle();
    results.add(_Check(
      'owner trips DELETE is no-op (no hard delete policy)',
      cascadeTripAfterUserDelete != null,
    ));

    var cascadeTripDeleteOk = false;
    if (serviceClient != null) {
      try {
        await serviceClient.from('trips').delete().eq('id', cascadeTripId);
        cascadeTripDeleteOk = true;
      } catch (_) {}
    }
    final cascadeTripAfter = serviceClient == null
        ? null
        : await serviceClient
            .from('trips')
            .select('id')
            .eq('id', cascadeTripId)
            .maybeSingle();
    final cascadeTripRsvpsAfter = serviceClient == null
        ? const []
        : await serviceClient
            .from('trip_plan_item_rsvps')
            .select('id')
            .eq('plan_item_id', cascadeTripEventId);
    results.add(_Check(
      'delete trip with event + RSVP cascades',
      serviceClient != null &&
          (cascadeTripRsvpBefore as List).isNotEmpty &&
          cascadeTripDeleteOk &&
          cascadeTripAfter == null &&
          cascadeTripRsvpsAfter.isEmpty,
      detail: serviceClient == null
          ? 'set RLS_SERVICE_ROLE_KEY for cascade delete test'
          : null,
    ));

    await clientB.rpc('clear_event_rsvp', params: {
      'p_plan_item_id': eventActivityId,
    });
    final rsvpAfterWithdraw = await clientB
        .from('trip_plan_item_rsvps')
        .select('id')
        .eq('plan_item_id', eventActivityId)
        .eq('user_id', userB)
        .maybeSingle();
    results.add(_Check(
      'B withdraw own RSVP via RPC',
      rsvpAfterWithdraw == null,
    ));

    await clientB.rpc('set_event_rsvp', params: {
      'p_plan_item_id': eventActivityId,
      'p_status': 'maybe',
    });

    // --- S46 notifications ---
    if (serviceClient != null) {
      final noticeId = await serviceClient.rpc('record_notification', params: {
        'p_user_id': userB,
        'p_trip_id': tripId,
        'p_type': 'close_notice',
        'p_title': 'Trip is closing',
        'p_body': 'Smoke notice for member B',
        'p_route': '/trips/$tripId/close-report',
      }) as String;

      final aNotices =
          await clientA.from('notifications').select('id').eq('id', noticeId);
      results.add(_Check(
        'A cannot read B notifications',
        (aNotices as List).isEmpty,
      ));

      final bNotices = await clientB
          .from('notifications')
          .select('id, read_at')
          .eq('id', noticeId);
      results.add(_Check(
        'B sees own notification',
        (bNotices as List).length == 1 && bNotices.first['read_at'] == null,
      ));

      var insertBlocked = false;
      try {
        await clientA.from('notifications').insert({
          'user_id': userA,
          'type': 'close_notice',
          'title': 'blocked',
          'body': 'blocked',
        });
      } catch (_) {
        insertBlocked = true;
      }
      results.add(
          _Check('client INSERT into notifications blocked', insertBlocked));

      await clientB.rpc('mark_notification_read', params: {'p_id': noticeId});
      final readRow = await clientB
          .from('notifications')
          .select('read_at')
          .eq('id', noticeId)
          .single();
      results.add(_Check(
        'mark_notification_read sets read_at for caller',
        readRow['read_at'] != null,
      ));

      await serviceClient.rpc('record_notification', params: {
        'p_user_id': userA,
        'p_trip_id': tripId,
        'p_type': 'close_notice',
        'p_title': 'For A',
        'p_body': 'Unread for mark-all test',
        'p_route': '/trips/$tripId/close-report',
      });
      await clientA.rpc('mark_all_notifications_read');
      final aUnread = await clientA
          .from('notifications')
          .select('id')
          .eq('user_id', userA)
          .isFilter('read_at', null);
      results.add(_Check(
        'mark_all_notifications_read clears caller unread',
        (aUnread as List).isEmpty,
      ));
    } else {
      results.add(_Check(
        'S46 notifications (service role)',
        false,
        detail: 'set RLS_SERVICE_ROLE_KEY for notification smoke',
      ));
    }

    // --- S17 lifecycle (R3) — before B is removed ---
    await clientA.rpc('request_trip_close', params: {'p_trip_id': tripId});
    final closingRow = await clientA
        .from('trips')
        .select('lifecycle')
        .eq('id', tripId)
        .single();
    results.add(_Check('A request_trip_close → closing',
        closingRow['lifecycle'] == 'closing'));

    if (serviceClient != null) {
      final fifteenDaysAgo = DateTime.now()
          .toUtc()
          .subtract(const Duration(days: 15))
          .toIso8601String();
      await serviceClient.rpc('rls_smoke_set_close_notified_at', params: {
        'p_trip_id': tripId,
        'p_user_id': userA,
        'p_at': fifteenDaysAgo,
      });
      await serviceClient.rpc('run_trip_lifecycle_jobs');
      final unnotifiedBlocks = await clientA
          .from('trips')
          .select('lifecycle')
          .eq('id', tripId)
          .single();
      results.add(_Check(
        'un-notified member blocks deemed close',
        unnotifiedBlocks['lifecycle'] == 'closing',
      ));

      final eightDaysAgo = DateTime.now()
          .toUtc()
          .subtract(const Duration(days: 8))
          .toIso8601String();
      await serviceClient.rpc('rls_smoke_set_close_notified_at', params: {
        'p_trip_id': tripId,
        'p_user_id': userB,
        'p_at': eightDaysAgo,
      });
      await serviceClient.rpc('mark_close_reminder_sent', params: {
        'p_trip_id': tripId,
        'p_user_id': userB,
      });
      final remindedOnce = await clientB
          .from('trip_members')
          .select('close_reminded_at')
          .eq('trip_id', tripId)
          .eq('user_id', userB)
          .single();
      final firstReminded = remindedOnce['close_reminded_at'] as String?;
      await serviceClient.rpc('mark_close_reminder_sent', params: {
        'p_trip_id': tripId,
        'p_user_id': userB,
      });
      final remindedTwice = await clientB
          .from('trip_members')
          .select('close_reminded_at')
          .eq('trip_id', tripId)
          .eq('user_id', userB)
          .single();
      results.add(_Check(
        'day-7 reminder single-shot (close_reminded_at)',
        firstReminded != null &&
            remindedTwice['close_reminded_at'] == firstReminded,
      ));
    }

    await clientB.rpc('object_to_trip_close', params: {
      'p_trip_id': tripId,
      'p_reason': 'rls_smoke objection',
    });
    if (serviceClient != null) {
      await serviceClient.rpc('rls_smoke_set_close_requested_at', params: {
        'p_trip_id': tripId,
        'p_at': DateTime.now()
            .toUtc()
            .subtract(const Duration(days: 15))
            .toIso8601String(),
      });
      await serviceClient.rpc('run_trip_lifecycle_jobs');
      final objectedStillClosing = await clientA
          .from('trips')
          .select('lifecycle')
          .eq('id', tripId)
          .single();
      results.add(_Check(
        'objection holds trip in closing after window',
        objectedStillClosing['lifecycle'] == 'closing',
      ));

      await clientB
          .rpc('withdraw_close_objection', params: {'p_trip_id': tripId});
      final fifteenDaysAgo = DateTime.now()
          .toUtc()
          .subtract(const Duration(days: 15))
          .toIso8601String();
      for (final uid in [userA, userB]) {
        await serviceClient.rpc('rls_smoke_set_close_notified_at', params: {
          'p_trip_id': tripId,
          'p_user_id': uid,
          'p_at': fifteenDaysAgo,
        });
      }
      await serviceClient.rpc('run_trip_lifecycle_jobs');
    }

    final closedRow = await clientA
        .from('trips')
        .select('lifecycle')
        .eq('id', tripId)
        .single();
    results.add(_Check(
      'deemed close after window (silent member)',
      serviceClient != null && closedRow['lifecycle'] == 'closed',
      detail: serviceClient == null
          ? 'set RLS_SERVICE_ROLE_KEY for job tests'
          : null,
    ));

    var expenseOnClosedBlocked = false;
    try {
      await clientB.from('expenses').insert({
        'id': _uuid(),
        'trip_id': tripId,
        'payer_id': userB,
        'amount_cents': 100,
        'currency': 'EUR',
        'base_cents': 100,
        'fx_rate': 1,
        'description': 'blocked',
        'created_by': userB,
      });
    } catch (_) {
      expenseOnClosedBlocked = true;
    }
    results.add(_Check(
      'B INSERT expense on closed trip blocked',
      closedRow['lifecycle'] == 'closed' && expenseOnClosedBlocked,
    ));

    var rsvpOnClosedBlocked = false;
    try {
      await clientB.rpc('set_event_rsvp', params: {
        'p_plan_item_id': eventActivityId,
        'p_status': 'going',
      });
    } catch (_) {
      rsvpOnClosedBlocked = true;
    }
    results.add(_Check(
      'RSVP on closed trip blocked',
      closedRow['lifecycle'] == 'closed' && rsvpOnClosedBlocked,
    ));

    var withdrawOnClosedBlocked = false;
    if (closedRow['lifecycle'] == 'closed') {
      final beforeWithdraw = await clientB
          .from('trip_plan_item_rsvps')
          .select('id')
          .eq('plan_item_id', eventActivityId)
          .eq('user_id', userB)
          .maybeSingle();
      try {
        await clientB.rpc('clear_event_rsvp', params: {
          'p_plan_item_id': eventActivityId,
        });
      } catch (_) {
        withdrawOnClosedBlocked = true;
      }
      final afterWithdraw = await clientB
          .from('trip_plan_item_rsvps')
          .select('id')
          .eq('plan_item_id', eventActivityId)
          .eq('user_id', userB)
          .maybeSingle();
      results.add(_Check(
        'withdraw RSVP on closed trip blocked',
        beforeWithdraw != null &&
            (withdrawOnClosedBlocked || afterWithdraw != null),
      ));
    }

    var disputeBeforeSettleOk = false;
    if (closedRow['lifecycle'] == 'closed') {
      try {
        await clientB.rpc('respond_to_share', params: {
          'p_expense_id': bornCommittedId,
          'p_accept': false,
          'p_reason': 'dispute before settle confirm',
        });
        disputeBeforeSettleOk = true;
      } catch (_) {}
    }
    results.add(_Check(
      'member disputes own share on closed trip before settle confirm',
      disputeBeforeSettleOk,
    ));

    var disputeAfterSettleBlocked = false;
    String? a1SettlementId;
    if (closedRow['lifecycle'] == 'closed') {
      a1SettlementId = _uuid();
      try {
        await clientB.from('settlements').insert({
          'id': a1SettlementId,
          'trip_id': tripId,
          'from_user': userB,
          'to_user': userA,
          'amount_cents': 25,
          'currency': 'EUR',
        });
        await clientA
            .from('settlements')
            .update({'status': 'confirmed'}).eq('id', a1SettlementId);
        await clientA.rpc('respond_to_share', params: {
          'p_expense_id': bornCommittedId,
          'p_accept': false,
          'p_reason': 'dispute after settle confirm',
        });
      } catch (_) {
        disputeAfterSettleBlocked = true;
      }
    }
    results.add(_Check(
      'A1: settle confirm blocks further dispute for that member',
      disputeAfterSettleBlocked,
    ));

    if (serviceClient != null) {
      var forgedNoticeBlocked = false;
      try {
        await clientA
            .from('trip_members')
            .update({
              'close_notified_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('trip_id', tripId)
            .eq('user_id', userA);
      } catch (_) {
        forgedNoticeBlocked = true;
      }
      results.add(_Check(
        'client cannot forge close_notified_at',
        forgedNoticeBlocked,
      ));
    }

    var planInsertClosedBlocked = false;
    try {
      await clientB.from('trip_plan_items').insert({
        'id': _uuid(),
        'trip_id': tripId,
        'kind': 'flight',
        'title': 'blocked',
        'created_by': userB,
      });
    } catch (_) {
      planInsertClosedBlocked = true;
    }
    results.add(_Check(
      'B INSERT plan item on closed trip blocked',
      closedRow['lifecycle'] == 'closed' && planInsertClosedBlocked,
    ));

    var planUpdateClosedBlocked = false;
    try {
      await clientB
          .from('trip_plan_items')
          .update({'title': 'blocked update'}).eq('id', planItemId);
    } catch (_) {
      planUpdateClosedBlocked = true;
    }
    final planAfterUpdate = await clientA
        .from('trip_plan_items')
        .select('title')
        .eq('id', planItemId)
        .maybeSingle();
    results.add(_Check(
      'B UPDATE plan item on closed trip blocked',
      closedRow['lifecycle'] == 'closed' &&
          (planUpdateClosedBlocked ||
              planAfterUpdate?['title'] == 'RLS smoke hotel'),
    ));

    var planDeleteClosedBlocked = false;
    try {
      await clientB.from('trip_plan_items').delete().eq('id', planItemId);
    } catch (_) {
      planDeleteClosedBlocked = true;
    }
    final planStillThere = await clientA
        .from('trip_plan_items')
        .select('id')
        .eq('id', planItemId)
        .maybeSingle();
    results.add(_Check(
      'B DELETE plan item on closed trip blocked',
      closedRow['lifecycle'] == 'closed' &&
          (planDeleteClosedBlocked || planStillThere != null),
    ));

    var settlementOnClosedOk = false;
    if (closedRow['lifecycle'] == 'closed') {
      try {
        await clientB.from('settlements').insert({
          'id': _uuid(),
          'trip_id': tripId,
          'from_user': userB,
          'to_user': userA,
          'amount_cents': 50,
          'currency': 'EUR',
        });
        settlementOnClosedOk = true;
      } catch (_) {}
    }
    results.add(_Check(
      'B settlement write on closed trip allowed',
      settlementOnClosedOk,
    ));

    var budgetOnClosedBlocked = false;
    try {
      await clientA.rpc('set_trip_budget', params: {
        'p_trip_id': tripId,
        'p_mode': 'informational',
        'p_cents': 10000,
      });
    } catch (_) {
      budgetOnClosedBlocked = true;
    }
    results.add(_Check(
      'budget set on closed trip blocked',
      closedRow['lifecycle'] == 'closed' && budgetOnClosedBlocked,
    ));

    var fxOnClosedBlocked = false;
    try {
      await clientA.rpc('capture_trip_fx_rate', params: {
        'p_trip_id': tripId,
        'p_currency': 'GBP',
      });
    } catch (_) {
      fxOnClosedBlocked = true;
    }
    results.add(_Check(
      'FX capture on closed trip blocked',
      closedRow['lifecycle'] == 'closed' && fxOnClosedBlocked,
    ));

    // Cancel + co-admin guard on a throwaway pre-start trip
    final cancelTripId = _uuid();
    await clientA.rpc('create_trip', params: {
      'p_id': cancelTripId,
      'p_name': 'RLS cancel smoke',
      'p_start_date': DateTime.now()
          .toUtc()
          .add(const Duration(days: 30))
          .toIso8601String()
          .substring(0, 10),
    });

    final cancelEventId = _uuid();
    await clientA.from('trip_plan_items').insert({
      'id': cancelEventId,
      'trip_id': cancelTripId,
      'kind': 'activity',
      'title': 'cancelled event',
      'created_by': userA,
    });

    await clientA.rpc('cancel_trip', params: {'p_trip_id': cancelTripId});
    final cancelled = await clientA
        .from('trips')
        .select('lifecycle')
        .eq('id', cancelTripId)
        .single();
    results.add(
        _Check('A cancel pre-start', cancelled['lifecycle'] == 'cancelled'));

    var writeOnCancelledBlocked = false;
    try {
      await clientA.from('expenses').insert({
        'id': _uuid(),
        'trip_id': cancelTripId,
        'payer_id': userA,
        'amount_cents': 100,
        'currency': 'EUR',
        'base_cents': 100,
        'fx_rate': 1,
        'description': 'blocked',
        'created_by': userA,
      });
    } catch (_) {
      writeOnCancelledBlocked = true;
    }
    results.add(
        _Check('write on cancelled trip blocked', writeOnCancelledBlocked));

    var rsvpOnCancelledBlocked = false;
    try {
      await clientA.rpc('set_event_rsvp', params: {
        'p_plan_item_id': cancelEventId,
        'p_status': 'going',
      });
    } catch (_) {
      rsvpOnCancelledBlocked = true;
    }
    results
        .add(_Check('RSVP on cancelled trip blocked', rsvpOnCancelledBlocked));

    var budgetOnCancelledBlocked = false;
    try {
      await clientA.rpc('set_trip_budget', params: {
        'p_trip_id': cancelTripId,
        'p_mode': 'informational',
        'p_cents': 5000,
      });
    } catch (_) {
      budgetOnCancelledBlocked = true;
    }
    results.add(_Check(
      'budget set on cancelled trip blocked',
      budgetOnCancelledBlocked,
    ));

    var fxOnCancelledBlocked = false;
    try {
      await clientA.rpc('capture_trip_fx_rate', params: {
        'p_trip_id': cancelTripId,
        'p_currency': 'USD',
      });
    } catch (_) {
      fxOnCancelledBlocked = true;
    }
    results.add(_Check(
      'FX capture on cancelled trip blocked',
      fxOnCancelledBlocked,
    ));

    // dispute blocked — pre-start cancelled trip with its own committed expense + B share
    final cancelDisputeTripId = _uuid();
    final futureStart = DateTime.now()
        .toUtc()
        .add(const Duration(days: 30))
        .toIso8601String()
        .substring(0, 10);
    await clientA.rpc('create_trip', params: {
      'p_id': cancelDisputeTripId,
      'p_name': 'RLS cancel dispute smoke',
      'p_start_date': futureStart,
    });
    final cancelDisputeInvite = await clientA
        .from('invites')
        .insert({'trip_id': cancelDisputeTripId, 'created_by': userA})
        .select('token')
        .single();
    await clientB.rpc('join_trip',
        params: {'p_token': cancelDisputeInvite['token'] as String});
    final cancelDisputeExpenseId = _uuid();
    await clientA.from('expenses').insert({
      'id': cancelDisputeExpenseId,
      'trip_id': cancelDisputeTripId,
      'payer_id': userA,
      'amount_cents': 1000,
      'currency': 'EUR',
      'base_cents': 1000,
      'fx_rate': 1,
      'description': 'cancel dispute smoke',
      'created_by': userA,
    });
    await clientA.from('expense_shares').insert([
      {
        'id': _uuid(),
        'expense_id': cancelDisputeExpenseId,
        'user_id': userA,
        'share_cents': 500,
      },
      {
        'id': _uuid(),
        'expense_id': cancelDisputeExpenseId,
        'user_id': userB,
        'share_cents': 500,
      },
    ]);
    await clientA
        .rpc('cancel_trip', params: {'p_trip_id': cancelDisputeTripId});
    final cancelDisputeRow = await clientA
        .from('trips')
        .select('lifecycle')
        .eq('id', cancelDisputeTripId)
        .single();
    var disputeOnCancelledBlocked = false;
    try {
      await clientB.rpc('respond_to_share', params: {
        'p_expense_id': cancelDisputeExpenseId,
        'p_accept': false,
        'p_reason': 'blocked on cancelled',
      });
    } catch (_) {
      disputeOnCancelledBlocked = true;
    }
    results.add(_Check(
      'dispute on cancelled trip blocked',
      cancelDisputeRow['lifecycle'] == 'cancelled' && disputeOnCancelledBlocked,
    ));

    await clientA.rpc('set_member_role', params: {
      'p_trip_id': tripId,
      'p_user_id': userB,
      'p_role': 'co-admin',
    });
    var coAdminCancelBlocked = false;
    try {
      await clientB.rpc('cancel_trip', params: {'p_trip_id': tripId});
    } catch (_) {
      coAdminCancelBlocked = true;
    }
    results.add(_Check('co-admin cannot cancel trip', coAdminCancelBlocked));

    await clientA
        .from('trips')
        .update({'destination': 'RLS baseline'}).eq('id', tripId);

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
            fileOptions:
                const FileOptions(contentType: 'image/png', upsert: true),
          );
    } catch (_) {
      bUpsertBlocked = true;
    }
    results.add(_Check('B ex-member upsert blocked', bUpsertBlocked));

    var exMemberPlanBlocked = false;
    try {
      await clientB.from('trip_plan_items').insert({
        'id': _uuid(),
        'trip_id': tripId,
        'kind': 'other',
        'title': 'blocked',
        'created_by': userB,
      });
    } catch (_) {
      exMemberPlanBlocked = true;
    }
    results.add(_Check('B ex-member plan insert blocked', exMemberPlanBlocked));

    var exMemberRsvpBlocked = false;
    try {
      await clientB.rpc('set_event_rsvp', params: {
        'p_plan_item_id': eventActivityId,
        'p_status': 'going',
      });
    } catch (_) {
      exMemberRsvpBlocked = true;
    }
    results.add(_Check('B ex-member RSVP blocked', exMemberRsvpBlocked));

    // Storage remove() is silent on RLS deny — verify object survival, not throws.
    List<FileObject> bRemoveResult = [];
    try {
      bRemoveResult =
          await clientB.storage.from(_capturesBucket).remove([bStoragePath]);
    } catch (_) {}
    final bActuallyRemoved = bRemoveResult.any((f) => f.name == bStoragePath);
    results.add(_Check(
      'B ex-member delete no-op (not in removed list)',
      !bActuallyRemoved,
    ));

    final aSignedAfterBDelete = await clientA.storage
        .from(_capturesBucket)
        .createSignedUrl(bStoragePath, 60);
    final aFetchAfterBDelete = await http.get(Uri.parse(aSignedAfterBDelete));
    results.add(_Check(
      'B object survived ex-member delete',
      aFetchAfterBDelete.statusCode == 200,
    ));

    var cBlocked = false;
    try {
      await clientC.storage
          .from(_capturesBucket)
          .createSignedUrl(storagePath, 60);
    } catch (_) {
      cBlocked = true;
    }
    results.add(_Check('C outsider cannot sign receipt URL', cBlocked));

    final cTrips = await clientC.from('trips').select('id').eq('id', tripId);
    results.add(_Check('C zero trip rows', (cTrips as List).isEmpty));

    final cBalances = await clientC
        .from('trip_balances')
        .select('trip_id')
        .eq('trip_id', tripId);
    results
        .add(_Check('C zero trip_balances rows', (cBalances as List).isEmpty));

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
    results
        .add(_Check('C cannot self-insert trip_members', memberInsertBlocked));

    // --- S48 soft-close on end date (isolated from deemed-close) ---
    if (serviceClient != null) {
      final softCloseTripId = _uuid();
      final yesterday =
          DateTime.now().toUtc().subtract(const Duration(days: 1));
      final endDate =
          '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';

      await clientA.rpc('create_trip', params: {
        'p_id': softCloseTripId,
        'p_name':
            'RLS soft-close ${DateTime.now().toUtc().toIso8601String()}',
        'p_end_date': endDate,
      });

      var clientSoftCloseBlocked = false;
      try {
        await clientA.rpc('_enter_soft_close', params: {
          'p_trip_id': softCloseTripId,
        });
      } catch (_) {
        clientSoftCloseBlocked = true;
      }
      results.add(_Check(
        'S48 client cannot call _enter_soft_close',
        clientSoftCloseBlocked,
      ));

      await serviceClient.rpc('_enter_soft_close', params: {
        'p_trip_id': softCloseTripId,
      });

      final softRow = await clientA
          .from('trips')
          .select(
            'lifecycle, close_requested_at, soft_closed_at, soft_closed_by',
          )
          .eq('id', softCloseTripId)
          .single();
      results.add(_Check(
        'S48 soft_closed sets lifecycle only',
        softRow['lifecycle'] == 'soft_closed' &&
            softRow['close_requested_at'] == null &&
            softRow['soft_closed_at'] != null,
      ));
      results.add(_Check(
        'S48 soft_closed_by is owner',
        softRow['soft_closed_by'] == userA,
      ));

      final memberCloseCols = await clientA
          .from('trip_members')
          .select(
            'close_notified_at, close_accepted_at, close_objected_at',
          )
          .eq('trip_id', softCloseTripId);
      final memberRows =
          (memberCloseCols as List).cast<Map<String, dynamic>>();
      final noMemberCloseStamped = memberRows.every(
        (m) =>
            m['close_notified_at'] == null &&
            m['close_accepted_at'] == null &&
            m['close_objected_at'] == null,
      );
      results.add(_Check(
        'S48 soft_close leaves member close_* null',
        noMemberCloseStamped,
      ));

      var softClosedExpenseOk = false;
      try {
        final softInvite = await clientA
            .from('invites')
            .insert({'trip_id': softCloseTripId, 'created_by': userA})
            .select('token')
            .single();
        await clientB.rpc('join_trip', params: {
          'p_token': softInvite['token'],
        });
        await clientB.from('expenses').insert({
          'id': _uuid(),
          'trip_id': softCloseTripId,
          'payer_id': userB,
          'amount_cents': 500,
          'currency': 'EUR',
          'base_cents': 500,
          'fx_rate': 1,
          'description': 'S48 soft_closed writable',
          'created_by': userB,
        });
        softClosedExpenseOk = true;
      } catch (_) {}
      results.add(_Check(
        'S48 soft_closed trip remains writable',
        softClosedExpenseOk,
      ));

      var forgeSoftClosedBlocked = false;
      try {
        await clientA.from('trips').update({
          'soft_closed_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', softCloseTripId);
      } catch (_) {
        forgeSoftClosedBlocked = true;
      }
      results.add(_Check(
        'S48 client cannot forge soft_closed_at',
        forgeSoftClosedBlocked,
      ));

      final wrapId1 = await serviceClient.rpc('record_notification', params: {
        'p_user_id': userA,
        'p_trip_id': softCloseTripId,
        'p_type': 'wrapped_trip',
        'p_title': 'Your trip wrapped',
        'p_body': 'Your trip wrapped — relive it?',
        'p_route': '/trips/$softCloseTripId',
      });
      final wrapId2 = await serviceClient.rpc('record_notification', params: {
        'p_user_id': userA,
        'p_trip_id': softCloseTripId,
        'p_type': 'wrapped_trip',
        'p_title': 'Your trip wrapped',
        'p_body': 'Your trip wrapped — relive it?',
        'p_route': '/trips/$softCloseTripId',
      });
      results.add(_Check(
        'S48 wrapped_trip unique index blocks duplicate',
        wrapId1 != null && wrapId2 == null,
      ));

      await clientA.rpc('reopen_from_soft_close', params: {
        'p_trip_id': softCloseTripId,
      });
      final reopenedRow = await clientA
          .from('trips')
          .select('lifecycle, soft_closed_at, reopened_at')
          .eq('id', softCloseTripId)
          .single();
      results.add(_Check(
        'S48 owner reopen clears soft_close and sets reopened_at',
        reopenedRow['lifecycle'] == 'active' &&
            reopenedRow['soft_closed_at'] == null &&
            reopenedRow['reopened_at'] != null,
      ));

      final softCloseTrip2 = _uuid();
      await clientA.rpc('create_trip', params: {
        'p_id': softCloseTrip2,
        'p_name': 'RLS soft-close member ${DateTime.now().toUtc()}',
        'p_end_date': endDate,
      });
      final token2 = (await clientA
              .from('invites')
              .insert({'trip_id': softCloseTrip2, 'created_by': userA})
              .select('token')
              .single())['token'];
      await clientB.rpc('join_trip', params: {'p_token': token2});
      await serviceClient.rpc('_enter_soft_close', params: {
        'p_trip_id': softCloseTrip2,
      });
      var memberReopenBlocked = false;
      try {
        await clientB.rpc('reopen_from_soft_close', params: {
          'p_trip_id': softCloseTrip2,
        });
      } catch (_) {
        memberReopenBlocked = true;
      }
      results.add(_Check(
        'S48 non-owner cannot reopen from soft_close',
        memberReopenBlocked,
      ));

      try {
        await clientA.from('trips').delete().eq('id', softCloseTripId);
        await clientA.from('trips').delete().eq('id', softCloseTrip2);
      } catch (_) {}
    } else {
      results.add(_Check(
        'S48 soft-close smoke skipped',
        false,
        detail: 'set RLS_SERVICE_ROLE_KEY for S48 soft-close smoke',
      ));
    }

    await clientA.from('suggestions').insert({
      'user_id': userA,
      'body': 'rls_smoke_${tripId}_suggestion',
      'category': 'other',
    });
    final bSuggestions = await clientB
        .from('suggestions')
        .select('id')
        .eq('body', 'rls_smoke_${tripId}_suggestion');
    results.add(
        _Check('B cannot read A suggestions', (bSuggestions as List).isEmpty));
  } catch (e, st) {
    stderr.writeln('Unexpected error: $e\n$st');
    results.add(_Check('unexpected error', false, detail: '$e'));
  } finally {
    await _cleanupStorageObject(
      results: results,
      bucket: _capturesBucket,
      path: storagePath,
      removeClient: clientA,
      verifyClient: clientA,
    );
    await _cleanupStorageObject(
      results: results,
      bucket: _capturesBucket,
      path: bStoragePath,
      removeClient: clientB,
      verifyClient: clientA,
      fallbackRemoveClient: serviceClient,
    );
    await _cleanupStorageObject(
      results: results,
      bucket: _avatarsBucket,
      path: aAvatarPath,
      removeClient: clientA,
      verifyClient: clientA,
    );
    await _cleanupStorageObject(
      results: results,
      bucket: _avatarsBucket,
      path: bAvatarPath,
      removeClient: clientB,
      verifyClient: clientB ?? clientA,
    );
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

Future<void> _cleanupStorageObject({
  required List<_Check> results,
  required String bucket,
  required String? path,
  required SupabaseClient? removeClient,
  required SupabaseClient? verifyClient,
  SupabaseClient? fallbackRemoveClient,
}) async {
  if (path == null) return;
  final label = 'cleanup storage $bucket/$path';
  if (removeClient == null || verifyClient == null) {
    results.add(_Check(label, false, detail: 'missing cleanup client'));
    return;
  }

  Object? removeError;
  try {
    await removeClient.storage.from(bucket).remove([path]);
  } catch (e) {
    removeError = e;
  }

  var stillExists = await _storageObjectExists(
    client: verifyClient,
    bucket: bucket,
    path: path,
  );
  var usedFallback = false;
  Object? fallbackError;
  if (stillExists && fallbackRemoveClient != null) {
    usedFallback = true;
    try {
      await fallbackRemoveClient.storage.from(bucket).remove([path]);
    } catch (e) {
      fallbackError = e;
    }
    stillExists = await _storageObjectExists(
      client: fallbackRemoveClient,
      bucket: bucket,
      path: path,
    );
  }

  results.add(_Check(
    label,
    !stillExists,
    detail: stillExists
        ? 'object still fetchable'
            '${removeError == null ? '' : '; remove: $removeError'}'
            '${fallbackError == null ? '' : '; fallback: $fallbackError'}'
        : usedFallback
            ? 'removed with service fallback'
            : null,
  ));
}

Future<bool> _storageObjectExists({
  required SupabaseClient client,
  required String bucket,
  required String path,
}) async {
  try {
    final signed = await client.storage.from(bucket).createSignedUrl(path, 60);
    final response = await http.get(Uri.parse(signed));
    return response.statusCode == 200;
  } catch (_) {
    return false;
  }
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

Future<int?> _netCents(
  SupabaseClient client,
  String tripId,
  String userId,
) async {
  final row = await client
      .from('trip_balances')
      .select('net_cents')
      .eq('trip_id', tripId)
      .eq('user_id', userId)
      .maybeSingle();
  return row == null ? null : (row['net_cents'] as num).toInt();
}

Future<bool> _selectDeniedOrEmpty(SupabaseClient client, String table) async {
  try {
    final rows = await client.from(table).select().limit(1);
    return (rows as List).isEmpty;
  } catch (_) {
    return true;
  }
}

class _Check {
  _Check(this.name, this.pass, {this.detail});
  final String name;
  final bool pass;
  final String? detail;
}

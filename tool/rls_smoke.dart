// Executable RLS + storage policy smoke test against the cloud Supabase project.
//
// Prerequisites (create once in Supabase Auth dashboard — password users):
//   RLS_USER_A_EMAIL / RLS_USER_A_PASSWORD — trip owner
//   RLS_USER_B_EMAIL / RLS_USER_B_PASSWORD — joins via invite
//   RLS_USER_C_EMAIL / RLS_USER_C_PASSWORD — outsider (never joins)
//   RLS_SERVICE_ROLE_KEY — lifecycle job + backdate tests (S17)
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

    final userB = clientB.auth.currentUser!.id;

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
    results.add(_Check('member cannot commit proposed expense', memberCommitBlocked));

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
      bShareRow['response'] == 'rejected' && aShareRow['response'] == 'accepted',
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
    await clientB.rpc('join_trip', params: {'p_token': voidInvite['token'] as String});
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
    await clientA.rpc('commit_expense', params: {'p_expense_id': voidExpenseId});
    final voidNetCommitted = await _netCents(clientB, voidTripId, userB);
    await clientA.rpc('void_expense', params: {'p_expense_id': voidExpenseId});
    final voidNetAfterVoid = await _netCents(clientB, voidTripId, userB);
    results.add(_Check(
      'void/cancelled expense leaves net_cents',
      voidNetCommitted != voidBaseline && voidNetAfterVoid == voidBaseline,
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

    // --- S16 role cases (R1) — before B is removed from trip ---
    await clientA
        .from('trips')
        .update({'destination': 'RLS baseline'})
        .eq('id', tripId);

    await clientB
        .from('trips')
        .update({'destination': 'Member edit'})
        .eq('id', tripId);
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
    results.add(_Check('A promotes B to co-admin', bRole['role'] == 'co-admin'));

    await clientB
        .from('trips')
        .update({'destination': 'Co-admin edit'})
        .eq('id', tripId);
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
        .update({'destination': 'RLS baseline'})
        .eq('id', tripId);

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

    // --- S17 lifecycle (R3) — before B is removed ---
    await clientA.rpc('request_trip_close', params: {'p_trip_id': tripId});
    final closingRow = await clientA
        .from('trips')
        .select('lifecycle')
        .eq('id', tripId)
        .single();
    results.add(_Check('A request_trip_close → closing', closingRow['lifecycle'] == 'closing'));

    await clientB.rpc('object_to_trip_close', params: {
      'p_trip_id': tripId,
      'p_reason': 'rls_smoke objection',
    });
    final serviceKey = Platform.environment['RLS_SERVICE_ROLE_KEY'];
    SupabaseClient? serviceClient;
    if (serviceKey != null && serviceKey.isNotEmpty) {
      serviceClient = SupabaseClient(url, serviceKey);
      await serviceClient.rpc('rls_smoke_set_close_requested_at', params: {
        'p_trip_id': tripId,
        'p_at': DateTime.now().toUtc().subtract(const Duration(days: 15)).toIso8601String(),
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

      await clientB.rpc('withdraw_close_objection', params: {'p_trip_id': tripId});
      await serviceClient.rpc('rls_smoke_set_close_requested_at', params: {
        'p_trip_id': tripId,
        'p_at': DateTime.now().toUtc().subtract(const Duration(days: 15)).toIso8601String(),
      });
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
      detail: serviceClient == null ? 'set RLS_SERVICE_ROLE_KEY for job tests' : null,
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

    var disputeOnClosedOk = false;
    if (closedRow['lifecycle'] == 'closed') {
      try {
        await clientB.rpc('respond_to_share', params: {
          'p_expense_id': bornCommittedId,
          'p_accept': false,
          'p_reason': 'dispute after close',
        });
        disputeOnClosedOk = true;
      } catch (_) {}
    }
    results.add(_Check(
      'member disputes own share on closed trip allowed',
      disputeOnClosedOk,
    ));

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
          .update({'title': 'blocked update'})
          .eq('id', planItemId);
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

    // Cancel + co-admin guard on a throwaway pre-start trip
    final cancelTripId = _uuid();
    await clientA.rpc('create_trip', params: {
      'p_id': cancelTripId,
      'p_name': 'RLS cancel smoke',
      'p_start_date': DateTime.now().toUtc().add(const Duration(days: 30)).toIso8601String().substring(0, 10),
    });
    await clientA.rpc('cancel_trip', params: {'p_trip_id': cancelTripId});
    final cancelled = await clientA
        .from('trips')
        .select('lifecycle')
        .eq('id', cancelTripId)
        .single();
    results.add(_Check('A cancel pre-start', cancelled['lifecycle'] == 'cancelled'));

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
    results.add(_Check('write on cancelled trip blocked', writeOnCancelledBlocked));

    // dispute blocked — pre-start cancelled trip with its own committed expense + B share
    final cancelDisputeTripId = _uuid();
    final futureStart =
        DateTime.now().toUtc().add(const Duration(days: 30)).toIso8601String().substring(0, 10);
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
    await clientB.rpc('join_trip', params: {'p_token': cancelDisputeInvite['token'] as String});
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
    await clientA.rpc('cancel_trip', params: {'p_trip_id': cancelDisputeTripId});
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
        .update({'destination': 'RLS baseline'})
        .eq('id', tripId);

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

class _Check {
  _Check(this.name, this.pass, {this.detail});
  final String name;
  final bool pass;
  final String? detail;
}

import 'package:app_core/app_core.dart';

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:share_plus/share_plus.dart';

import '../shared/vamo_slidable_row.dart';
import '../expenses/expenses_providers.dart';

import '../invites/contact_invite_flow.dart';

import '../invites/contact_invite_gateway.dart';

import '../invites/invite_analytics.dart';

import '../invites/invite_channel.dart';

import '../invites/invite_labels.dart';

import '../invites/invite_qr_show_sheet.dart';

import '../invites/invites_repository.dart';

import 'trips_providers.dart';

import 'trips_repository.dart';



enum _InviteMethod { textMessage, email, shareLink, qr }



/// Slice 5 — roster + invite link share. S16 — owner co-admin grants.

class MembersTab extends ConsumerStatefulWidget {

  const MembersTab({

    super.key,

    required this.tripId,

    required this.inviteLabels,

    this.contactInviteGateway,

    this.contactInviteShare,

  });



  final String tripId;

  final InviteLabels inviteLabels;



  /// Test override for [ContactInviteGateway].

  final ContactInviteGateway? contactInviteGateway;



  /// Test override for the platform share sheet used by contact fallback.

  final ContactInviteShare? contactInviteShare;



  @override

  ConsumerState<MembersTab> createState() => MembersTabState();

}



class MembersTabState extends ConsumerState<MembersTab> {

  /// Opens share, contact, or QR invite picker (trip-home FAB on Members tab).

  Future<void> openInviteFlow() => _showInvitePicker();



  bool _sharing = false;

  bool _showingQr = false;

  String? _roleBusyUserId;



  /// Started on invite tap only — browsing members is not an invite attempt.

  FlowTracker? _inviteFlow;



  ContactInviteGateway get _contactGateway =>

      widget.contactInviteGateway ?? ref.read(contactInviteGatewayProvider);



  bool get _contactInviteSupported => _contactGateway.isSupported;



  @override

  void dispose() {

    _inviteFlow?.abandonIfIncomplete();

    super.dispose();

  }



  @override

  Widget build(BuildContext context) {

    final labels = widget.inviteLabels;

    final colors = context.vamoColors;

    final members = ref.watch(tripMembersForExpenseProvider(widget.tripId));

    final trip = ref.watch(tripDetailProvider(widget.tripId));

    final currentUserId = ref.watch(currentUserProvider)?.id;

    final isOwner = trip.valueOrNull?.ownerId == currentUserId;



    return members.when(

      loading: () => const Center(child: CircularProgressIndicator()),

      error: (e, _) => AppErrorState(

        screen: 'trip_home',

        message: formatActionFailureMessage(e),

        kind: classifyActionFailureKind(e),

        onRetry: () =>

            ref.invalidate(tripMembersForExpenseProvider(widget.tripId)),

      ),

      data: (list) {

        return ListView(

          padding: const EdgeInsets.all(16),

          children: [

            Text(

              labels.membersVamigosTitle,

              style: Theme.of(context).textTheme.titleMedium?.copyWith(

                    color: colors.onSurface,

                    fontWeight: FontWeight.w700,

                  ),

            ),

            const SizedBox(height: 4),

            Text(

              list.length == 1

                  ? labels.membersInviteHintSolo

                  : labels.membersCountOnTrip(list.length),

              style: Theme.of(context)

                  .textTheme

                  .bodySmall

                  ?.copyWith(color: colors.onSurfaceMuted),

            ),

            const SizedBox(height: 16),

            ...list.map(

              (m) => _MemberRow(

                displayName: m.displayName,

                subtitle: m.userId == currentUserId

                    ? 'You · ${TripMemberRoles.label(m.role)}'

                    : TripMemberRoles.label(m.role),

                roleActions: _roleSlidableActions(

                  labels: labels,

                  colors: colors,

                  isOwner: isOwner,

                  memberUserId: m.userId,

                  memberRole: m.role,

                  currentUserId: currentUserId,

                ),

                busy: _roleBusyUserId == m.userId,

              ),

            ),

            const SizedBox(height: 24),

            FilledButton.icon(

              onPressed: _sharing || _showingQr ? null : openInviteFlow,

              icon: _sharing || _showingQr

                  ? const SizedBox(

                      width: 20,

                      height: 20,

                      child: CircularProgressIndicator(

                        strokeWidth: 2,

                        color: Colors.white,

                      ),

                    )

                  : const Icon(Icons.person_add_outlined),

              label: Text(labels.inviteAction),

            ),

            const SizedBox(height: 8),

            Text(

              labels.membersShareFootnote,

              textAlign: TextAlign.center,

              style: Theme.of(context)

                  .textTheme

                  .bodySmall

                  ?.copyWith(color: colors.onSurfaceMuted),

            ),

          ],

        );

      },

    );

  }



  List<SlidableAction>? _roleSlidableActions({

    required InviteLabels labels,

    required VamoSemanticColors colors,

    required bool isOwner,

    required String memberUserId,

    required String memberRole,

    required String? currentUserId,

  }) {

    if (!isOwner ||

        memberUserId == currentUserId ||

        TripMemberRoles.isOwner(memberRole)) {

      return null;

    }

    final label = TripMemberRoles.isCoAdmin(memberRole)

        ? labels.membersRemoveCoAdmin

        : labels.membersMakeCoAdmin;

    final role = TripMemberRoles.isCoAdmin(memberRole)

        ? TripMemberRoles.member

        : TripMemberRoles.coAdmin;

    return [

      SlidableAction(

        onPressed: (_) => _onRoleAction(role, memberUserId),

        backgroundColor: colors.secondary,

        foregroundColor: colors.onSecondary,

        icon: Icons.admin_panel_settings_outlined,

        label: label,

      ),

    ];

  }



  Future<void> _onRoleAction(String role, String userId) async {

    setState(() => _roleBusyUserId = userId);

    try {

      await ref.read(tripsRepositoryProvider).setMemberRole(

            tripId: widget.tripId,

            userId: userId,

            role: role,

          );

      ref.invalidate(tripMembersForExpenseProvider(widget.tripId));

    } catch (e) {

      if (!mounted) return;

      showActionError(

        context,

        ref,

        screen: 'trip_home',

        action: 'set_member_role',

        error: e,

      );

    } finally {

      if (mounted) setState(() => _roleBusyUserId = null);

    }

  }



  Future<void> _showInvitePicker() => _showInviteMethodSheet();



  Future<void> _showInviteMethodSheet() async {

    final labels = widget.inviteLabels;

    final method = await showModalBottomSheet<_InviteMethod>(

      context: context,

      showDragHandle: true,

      builder: (ctx) => SafeArea(

        child: SingleChildScrollView(

          child: Column(

            mainAxisSize: MainAxisSize.min,

            children: [

            if (_contactInviteSupported)

              ListTile(

                leading: const Icon(Icons.sms_outlined),

                title: Text(labels.contactMethodTextMessage),

                onTap: () => Navigator.pop(ctx, _InviteMethod.textMessage),

              ),

            if (_contactInviteSupported)

              ListTile(

                leading: const Icon(Icons.email_outlined),

                title: Text(labels.contactMethodEmail),

                onTap: () => Navigator.pop(ctx, _InviteMethod.email),

              ),

            ListTile(

              leading: const Icon(Icons.share_outlined),

              title: Text(labels.contactMethodShareLink),

              subtitle: Text(labels.shareJoinLink),

              onTap: () => Navigator.pop(ctx, _InviteMethod.shareLink),

            ),

            ListTile(

              leading: const Icon(Icons.qr_code_2_outlined),

              title: Text(labels.showQr),

              subtitle: Text(labels.qrCaption),

              onTap: () => Navigator.pop(ctx, _InviteMethod.qr),

            ),

          ],

          ),

        ),

      ),

    );

    if (!mounted || method == null) return;



    switch (method) {

      case _InviteMethod.textMessage:

        await runContactInviteFlow(

          context: context,

          ref: ref,

          tripId: widget.tripId,

          labels: labels,

          gateway: _contactGateway,

          shareInvite: widget.contactInviteShare,

          initialMethod: ContactInviteMethod.textMessage,

        );

      case _InviteMethod.email:

        await runContactInviteFlow(

          context: context,

          ref: ref,

          tripId: widget.tripId,

          labels: labels,

          gateway: _contactGateway,

          shareInvite: widget.contactInviteShare,

          initialMethod: ContactInviteMethod.email,

        );

      case _InviteMethod.shareLink:

        await _shareInvite();

      case _InviteMethod.qr:

        await _showQr();

    }

  }



  Future<void> _shareInvite() async {

    _inviteFlow = FlowTracker(

      flow: 'invite',

      analytics: ref.read(analyticsProvider),

    );



    setState(() => _sharing = true);

    try {

      final labels = widget.inviteLabels;

      final token = await ref

          .read(invitesRepositoryProvider)

          .getOrCreateInviteToken(widget.tripId);

      final web = InviteUrls.webInviteLink(token);

      final app = InviteUrls.appInviteUri(token);

      final body = labels.contactInviteBody(web, app.toString());



      await Share.share(body, subject: labels.contactInviteSubject);

      captureMemberInvitedShow(

        ref.read(analyticsProvider),

        tripId: widget.tripId,

        channel: InviteChannel.link,

      );

      _inviteFlow?.complete();

    } catch (e) {

      if (!mounted) return;

      showActionError(

        context,

        ref,

        screen: 'trip_home',

        action: 'create_invite',

        error: e,

      );

    } finally {

      if (mounted) setState(() => _sharing = false);

    }

  }



  Future<void> _showQr() async {

    setState(() => _showingQr = true);

    try {

      final token = await ref

          .read(invitesRepositoryProvider)

          .getOrCreateInviteToken(widget.tripId);

      final tripName =

          ref.read(tripDetailProvider(widget.tripId)).valueOrNull?.name ??

              'Trip';

      if (!mounted) return;

      await showInviteQrSheet(

        context: context,

        analytics: ref.read(analyticsProvider),

        tripId: widget.tripId,

        tripName: tripName,

        token: token,

        labels: widget.inviteLabels,

      );

    } catch (e) {

      if (!mounted) return;

      showActionError(

        context,

        ref,

        screen: 'trip_home',

        action: 'show_invite_qr',

        error: e,

      );

    } finally {

      if (mounted) setState(() => _showingQr = false);

    }

  }

}



class _MemberRow extends StatelessWidget {

  const _MemberRow({

    required this.displayName,

    required this.subtitle,

    required this.roleActions,

    required this.busy,

  });



  final String displayName;

  final String subtitle;

  final List<SlidableAction>? roleActions;

  final bool busy;



  @override

  Widget build(BuildContext context) {

    final tile = Card(

      child: ListTile(

        leading: VamoAvatar(displayName: displayName, radius: 20),

        title: Text(displayName),

        subtitle: Text(subtitle),

        trailing: busy

            ? const SizedBox(

                width: 24,

                height: 24,

                child: CircularProgressIndicator(strokeWidth: 2),

              )

            : null,

      ),

    );



    if (roleActions == null || roleActions!.isEmpty) return tile;

    final roleLabel = roleActions!.first.label ?? 'Role';

    return VamoSlidableRow(
      editLabel: roleLabel,
      deleteLabel: roleLabel,
      deleteConfirmTitle: roleLabel,
      deleteConfirmAction: roleLabel,
      cancelLabel: 'Cancel',
      startActions: roleActions,
      child: tile,
    );

  }

}


import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

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
                    color: AppColors.ink,
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
                  ?.copyWith(color: AppColors.graphite),
            ),
            const SizedBox(height: 16),
            ...list.map(
              (m) => Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.blush,
                    child: Text(
                      m.displayName.isNotEmpty
                          ? m.displayName[0].toUpperCase()
                          : '?',
                      style: const TextStyle(color: AppColors.ink),
                    ),
                  ),
                  title: Text(m.displayName),
                  subtitle: Text(
                    m.userId == currentUserId
                        ? 'You · ${TripMemberRoles.label(m.role)}'
                        : TripMemberRoles.label(m.role),
                  ),
                  trailing: _roleTrailing(
                    isOwner: isOwner,
                    memberUserId: m.userId,
                    memberRole: m.role,
                    currentUserId: currentUserId,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _sharing ? null : _shareInvite,
                    icon: _sharing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.share_outlined),
                    label: Text(labels.inviteVamigos),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _showingQr ? null : _showQr,
                    icon: _showingQr
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.qr_code_2_outlined),
                    label: Text(labels.showQr),
                  ),
                ),
              ],
            ),
            if (_contactInviteSupported) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _startContactInvite,
                icon: const Icon(Icons.contacts_outlined),
                label: Text(labels.inviteFromContacts),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              labels.membersShareFootnote,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.graphite),
            ),
          ],
        );
      },
    );
  }

  Widget? _roleTrailing({
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
    if (_roleBusyUserId == memberUserId) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return PopupMenuButton<String>(
      onSelected: (value) => _onRoleAction(value, memberUserId),
      itemBuilder: (context) {
        if (TripMemberRoles.isCoAdmin(memberRole)) {
          return [
            const PopupMenuItem(
              value: 'member',
              child: Text('Remove co-admin'),
            ),
          ];
        }
        return [
          const PopupMenuItem(
            value: 'co-admin',
            child: Text('Make co-admin'),
          ),
        ];
      },
    );
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

  Future<void> _showInvitePicker() async {
    final labels = widget.inviteLabels;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: Text(labels.inviteVamigos),
              subtitle: Text(labels.shareJoinLink),
              onTap: () {
                Navigator.pop(ctx);
                _shareInvite();
              },
            ),
            if (_contactInviteSupported)
              ListTile(
                leading: const Icon(Icons.contacts_outlined),
                title: Text(labels.inviteFromContacts),
                onTap: () {
                  Navigator.pop(ctx);
                  _startContactInvite();
                },
              ),
            ListTile(
              leading: const Icon(Icons.qr_code_2_outlined),
              title: Text(labels.showQr),
              subtitle: Text(labels.qrCaption),
              onTap: () {
                Navigator.pop(ctx);
                _showQr();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _startContactInvite() => runContactInviteFlow(
        context: context,
        ref: ref,
        tripId: widget.tripId,
        labels: widget.inviteLabels,
        gateway: _contactGateway,
        shareInvite: widget.contactInviteShare,
      );

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

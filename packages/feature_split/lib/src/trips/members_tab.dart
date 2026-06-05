import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../expenses/expenses_providers.dart';
import '../invites/invites_repository.dart';

/// Slice 5 — roster + invite link share.
class MembersTab extends ConsumerStatefulWidget {
  const MembersTab({super.key, required this.tripId});

  final String tripId;

  @override
  ConsumerState<MembersTab> createState() => _MembersTabState();
}

class _MembersTabState extends ConsumerState<MembersTab> {
  bool _sharing = false;
  /// Started on invite tap only — browsing members is not an invite attempt.
  FlowTracker? _inviteFlow;

  @override
  void dispose() {
    _inviteFlow?.abandonIfIncomplete();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final members = ref.watch(tripMembersForExpenseProvider(widget.tripId));
    final currentUserId = ref.watch(currentUserProvider)?.id;

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
              'Vamigos',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              list.length == 1
                  ? 'Invite friends — balances unlock at 2+ people.'
                  : '${list.length} on this trip',
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
                        ? 'You · ${m.role}'
                        : m.role,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
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
              label: const Text('Invite Vamigos'),
            ),
            const SizedBox(height: 8),
            Text(
              'Share a link — they can join mid-trip. Opens Vamo or the store.',
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

  Future<void> _shareInvite() async {
    _inviteFlow = FlowTracker(
      flow: 'invite',
      analytics: ref.read(analyticsProvider),
    );

    setState(() => _sharing = true);
    try {
      final token = await ref
          .read(invitesRepositoryProvider)
          .getOrCreateInviteToken(widget.tripId);
      final web = InviteUrls.webInviteLink(token);
      final app = InviteUrls.appInviteUri(token);

      await Share.share(
        'Join my trip on Vamo!\n$web\n\n'
        'Have the app? Tap: $app',
        subject: 'Join my Vamo trip',
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
}

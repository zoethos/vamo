import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'trips_models.dart';
import 'trips_providers.dart';
import 'trips_repository.dart';

/// Closing / closed lifecycle banner and member actions (S17 / R3).
class TripLifecycleBanner extends ConsumerWidget {
  const TripLifecycleBanner({super.key, required this.tripId, required this.detail});

  final String tripId;
  final TripDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lifecycle = TripLifecycle.parse(detail.lifecycle);
    final userId = ref.watch(authRepositoryProvider).currentUser?.id;
    final isOwner = userId != null && userId == detail.ownerId;
    final member = ref.watch(tripMyMemberProvider(tripId)).valueOrNull;
    final hasObjection = ref.watch(tripHasCloseObjectionProvider(tripId)).valueOrNull ?? false;
    final repo = ref.read(tripsRepositoryProvider);

    if (lifecycle.isReadOnly) {
      return _Banner(
        color: AppColors.blush,
        message: lifecycle == TripLifecycle.cancelled
            ? 'Trip cancelled — no further activity.'
            : 'Trip closed — settling still open.',
      );
    }

    if (lifecycle == TripLifecycle.closing) {
      final days = closeReviewDaysRemaining(
        detail.closeRequestedAt,
        DateTime.now().toUtc(),
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Banner(
            color: AppColors.goLime.withValues(alpha: 0.35),
            message: days == null
                ? 'Trip is closing — review balances and respond.'
                : 'Trip closes in $days day${days == 1 ? '' : 's'} unless someone objects.',
          ),
          if (hasObjection)
            const Padding(
              padding: EdgeInsetsDirectional.only(top: 4),
              child: Text(
                'A member objected to closing — discuss or owner may close anyway.',
                style: TextStyle(color: AppColors.coralText, fontSize: 13),
              ),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (member?.closeAcceptedAt == null &&
                  member?.closeObjectedAt == null) ...[
                FilledButton(
                  onPressed: () => _run(context, ref, () => repo.acceptTripClose(tripId)),
                  child: const Text('Accept close'),
                ),
                OutlinedButton(
                  onPressed: () => _showObjectDialog(context, ref, repo),
                  child: const Text('Object…'),
                ),
              ],
              if (member?.closeObjectedAt != null)
                OutlinedButton(
                  onPressed: () => _run(
                    context,
                    ref,
                    () => repo.withdrawCloseObjection(tripId),
                  ),
                  child: const Text('Withdraw objection'),
                ),
              if (isOwner && hasObjection)
                OutlinedButton(
                  onPressed: () => _confirmForce(context, ref, repo),
                  child: const Text('Close anyway'),
                ),
            ],
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (member?.completedAt == null)
          OutlinedButton(
            onPressed: () => _confirmDone(context, ref, repo),
            child: const Text("I'm done"),
          ),
        if (isOwner) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton(
                onPressed: () => _run(
                  context,
                  ref,
                  () => repo.requestTripClose(tripId),
                ),
                child: const Text('Request close'),
              ),
              if (_canCancel(detail))
                OutlinedButton(
                  onPressed: () => _confirmCancel(context, ref, repo),
                  child: const Text('Cancel trip'),
                ),
            ],
          ),
        ],
      ],
    );
  }

  bool _canCancel(TripDetail detail) {
    final start = detail.startDate;
    if (start == null) return true;
    final parsed = DateTime.tryParse(start);
    if (parsed == null) return true;
    final today = DateTime.now();
    final startDay = DateTime(parsed.year, parsed.month, parsed.day);
    final todayDay = DateTime(today.year, today.month, today.day);
    return startDay.isAfter(todayDay);
  }

  Future<void> _confirmDone(
    BuildContext context,
    WidgetRef ref,
    TripsRepository repo,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Mark yourself done?"),
        content: const Text(
          'You can still log expenses until the trip closes. '
          'When everyone is done, the close review starts.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not yet')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("I'm done")),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await _run(context, ref, () => repo.markTripMemberComplete(tripId));
    }
  }

  Future<void> _confirmForce(
    BuildContext context,
    WidgetRef ref,
    TripsRepository repo,
  ) async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Close anyway?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'An objection is on record. Force-close keeps it visible in the close report.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(labelText: 'Type CLOSE to confirm'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Back')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim() == 'CLOSE'),
            child: const Text('Close trip'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (ok == true && context.mounted) {
      await _run(context, ref, () => repo.forceCloseTrip(tripId));
    }
  }

  Future<void> _confirmCancel(
    BuildContext context,
    WidgetRef ref,
    TripsRepository repo,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel this trip?'),
        content: const Text('Only possible before the start date. Members will be notified.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cancel trip')),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await _run(context, ref, () => repo.cancelTrip(tripId));
    }
  }

  Future<void> _showObjectDialog(
    BuildContext context,
    WidgetRef ref,
    TripsRepository repo,
  ) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Object to closing'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Reason (required)',
            hintText: 'What still needs resolving?',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Back')),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isEmpty) return;
              Navigator.pop(ctx, text);
            },
            child: const Text('Submit objection'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (reason != null && context.mounted) {
      await _run(
        context,
        ref,
        () => repo.objectToTripClose(tripId: tripId, reason: reason),
      );
    }
  }

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (e) {
      if (!context.mounted) return;
      showActionError(
        context,
        ref,
        screen: 'trip_home',
        action: 'lifecycle',
        error: e,
      );
    }
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.color, required this.message});

  final Color color;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.all(12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(message, style: const TextStyle(fontWeight: FontWeight.w600)),
    );
  }
}

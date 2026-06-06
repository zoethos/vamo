import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'trip_lifecycle_actions.dart';
import 'trip_lifecycle_labels.dart';
import 'trips_models.dart';
import 'trips_providers.dart';
import 'trips_repository.dart';

/// Closing / closed lifecycle banner only (S17.1 — active controls live in overflow).
class TripLifecycleBanner extends ConsumerWidget {
  const TripLifecycleBanner({
    super.key,
    required this.tripId,
    required this.detail,
    required this.labels,
  });

  final String tripId;
  final TripDetail detail;
  final TripLifecycleLabels labels;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lifecycle = TripLifecycle.parse(detail.lifecycle);
    final phase = resolveTripPhase(
      lifecycle: lifecycle,
      startDateIso: detail.startDate,
      now: DateTime.now(), // local — date-only phase (P1); closeReviewDaysRemaining below stays UTC vs the UTC timestamp
    );
    final userId = ref.watch(authRepositoryProvider).currentUser?.id;
    final isOwner = userId != null && userId == detail.ownerId;
    final member = ref.watch(tripMyMemberProvider(tripId)).valueOrNull;
    final hasObjection =
        ref.watch(tripHasCloseObjectionProvider(tripId)).valueOrNull ?? false;
    final repo = ref.read(tripsRepositoryProvider);

    if (phase == TripPhase.readOnly) {
      return _Banner(
        color: AppColors.blush,
        message: lifecycle == TripLifecycle.cancelled
            ? labels.cancelledBanner
            : labels.closedBanner,
      );
    }

    if (phase == TripPhase.closing) {
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
                ? labels.closingBannerGeneric
                : labels.closingBannerDays(days),
          ),
          if (hasObjection)
            Padding(
              padding: const EdgeInsetsDirectional.only(top: 4),
              child: Text(
                labels.objectionNotice,
                style: const TextStyle(color: AppColors.coralText, fontSize: 13),
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
                  onPressed: () => TripLifecycleActions.runLifecycleRpc(
                    context: context,
                    ref: ref,
                    action: () => repo.acceptTripClose(tripId),
                  ),
                  child: Text(labels.acceptClose),
                ),
                OutlinedButton(
                  onPressed: () => TripLifecycleActions.showObjectDialog(
                    context: context,
                    ref: ref,
                    tripId: tripId,
                    labels: labels,
                    repo: repo,
                  ),
                  child: Text(labels.objectToClose),
                ),
              ],
              if (member?.closeObjectedAt != null)
                OutlinedButton(
                  onPressed: () => TripLifecycleActions.runLifecycleRpc(
                    context: context,
                    ref: ref,
                    action: () => repo.withdrawCloseObjection(tripId),
                  ),
                  child: Text(labels.withdrawObjection),
                ),
              if (isOwner && hasObjection)
                OutlinedButton(
                  onPressed: () => TripLifecycleActions.confirmForceClose(
                    context: context,
                    ref: ref,
                    tripId: tripId,
                    labels: labels,
                    repo: repo,
                  ),
                  child: Text(labels.closeAnyway),
                ),
            ],
          ),
        ],
      );
    }

    return const SizedBox.shrink();
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

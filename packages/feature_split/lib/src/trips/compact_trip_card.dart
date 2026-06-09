import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../expenses/expenses_providers.dart';
import 'trip_format.dart';
import 'trip_visual_backdrop.dart';
import 'trips_models.dart';
import 'trips_providers.dart';

/// Smaller trip row with leading gradient thumbnail (S35).
class CompactTripCard extends ConsumerWidget {
  const CompactTripCard({
    super.key,
    required this.trip,
    required this.participantsLabel,
  });

  final TripSummary trip;
  final String Function(int count) participantsLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.vamoColors;
    final type = context.vamoType;
    final space = context.vamoSpace;
    final shape = context.vamoShape;
    final dates = formatTripDateRange(trip.startDate, trip.endDate);
    final memberCount =
        ref.watch(tripMembersForExpenseProvider(trip.id)).valueOrNull?.length;
    final backgroundImagePath =
        ref.watch(tripCardBackgroundImageProvider(trip.id));

    return Semantics(
      button: true,
      label: trip.name,
      child: Material(
        color: colors.surface,
        borderRadius: shape.cardBorderRadius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push(AppRoutes.trip(trip.id)),
          child: Padding(
            padding: EdgeInsetsDirectional.all(space.x3),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: shape.controlBorderRadius,
                  child: SizedBox(
                    width: 64,
                    height: 64,
                    child: TripVisualBackdrop(
                      tripName: trip.name,
                      destination: trip.destination,
                      backgroundImagePath: backgroundImagePath,
                    ),
                  ),
                ),
                SizedBox(width: space.x3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        trip.name,
                        style: type.titleSmall.copyWith(
                          color: colors.onSurface,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (dates != null || (memberCount ?? 0) > 0) ...[
                        SizedBox(height: space.x1),
                        Row(
                          children: [
                            if (dates != null)
                              Expanded(
                                child: Text(
                                  dates,
                                  style: type.bodySmall.copyWith(
                                    color: colors.onSurfaceMuted,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            if (dates != null &&
                                memberCount != null &&
                                memberCount > 0)
                              SizedBox(width: space.x2),
                            if (memberCount != null && memberCount > 0)
                              Text(
                                participantsLabel(memberCount),
                                style: type.bodySmall.copyWith(
                                  color: colors.onSurfaceMuted,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

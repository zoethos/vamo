import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../weather/weather_badge.dart';
import '../weather/weather_labels.dart';
import '../weather/weather_overlay.dart';
import '../expenses/expenses_providers.dart';
import 'trip_format.dart';
import 'trip_visual_backdrop.dart';
import 'trips_models.dart';
import 'trips_providers.dart';

/// Large hero card for the next upcoming trip (S35).
class FeaturedTripCard extends ConsumerWidget {
  const FeaturedTripCard({
    super.key,
    required this.trip,
    required this.participantsLabel,
    required this.weatherLabels,
  });

  final TripSummary trip;
  final String Function(int count) participantsLabel;
  final WeatherBadgeLabels weatherLabels;

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
          child: SizedBox(
            height: 220,
            child: TripVisualBackdrop(
              tripName: trip.name,
              destination: trip.destination,
              backgroundImagePath: backgroundImagePath,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  TripWeatherOverlay(trip: trip),
                  const GradientScrim(heightFactor: 0.7),
                  Positioned(
                    top: space.x4,
                    right: space.x4,
                    child: TripWeatherPreviewBadge(
                      trip: trip,
                      labels: weatherLabels,
                      onDark: true,
                    ),
                  ),
                  Padding(
                    padding: EdgeInsetsDirectional.all(space.x4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Spacer(),
                        Text(
                          trip.name,
                          style: type.headline.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (dates != null || (memberCount ?? 0) > 0) ...[
                          SizedBox(height: space.x2),
                          Row(
                            children: [
                              if (dates != null)
                                Expanded(
                                  child: Text(
                                    dates,
                                    style: type.bodyMedium.copyWith(
                                      color: Colors.white.withValues(alpha: 0.92),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              if (dates != null && (memberCount ?? 0) > 0)
                                SizedBox(width: space.x3),
                              if (memberCount != null && memberCount > 0)
                                Text(
                                  participantsLabel(memberCount),
                                  style: type.bodySmall.copyWith(
                                    color: Colors.white.withValues(alpha: 0.88),
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
      ),
    );
  }
}

import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../trips/trips_models.dart';
import 'weather_labels.dart';
import 'weather_models.dart';
import 'weather_providers.dart';

IconData weatherBucketIcon(ConditionBucket bucket) => switch (bucket) {
      ConditionBucket.sunny => Icons.wb_sunny_outlined,
      ConditionBucket.cloudy => Icons.cloud_outlined,
      ConditionBucket.rain => Icons.water_drop_outlined,
      ConditionBucket.thunderstorm => Icons.thunderstorm_outlined,
      ConditionBucket.snow => Icons.ac_unit_outlined,
      ConditionBucket.fog => Icons.foggy,
      ConditionBucket.unknown => Icons.wb_cloudy_outlined,
    };

class WeatherBadge extends StatelessWidget {
  const WeatherBadge({
    super.key,
    required this.preview,
    required this.labels,
    this.onDark = false,
  });

  final WeatherPreview preview;
  final WeatherBadgeLabels labels;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final colors = context.vamoColors;
    final type = context.vamoType;
    final space = context.vamoSpace;
    final temp = preview.tempHigh;
    final foreground = onDark ? Colors.white.withValues(alpha: 0.94) : colors.onSurface;
    final background = onDark
        ? Colors.black.withValues(alpha: 0.28)
        : colors.surfaceMuted.withValues(alpha: 0.92);

    return Semantics(
      label: temp == null
          ? labels.semanticLabel(preview.bucket)
          : '${labels.semanticLabel(preview.bucket)}, ${labels.temp(temp)}',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Padding(
          padding: EdgeInsetsDirectional.symmetric(
            horizontal: space.x2,
            vertical: space.x1,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                weatherBucketIcon(preview.bucket),
                size: 16,
                color: foreground,
              ),
              if (temp != null) ...[
                SizedBox(width: space.x1),
                Text(
                  labels.temp(temp),
                  style: type.labelMedium.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class TripWeatherPreviewBadge extends ConsumerWidget {
  const TripWeatherPreviewBadge({
    super.key,
    required this.trip,
    required this.labels,
    this.onDark = false,
  });

  final TripSummary trip;
  final WeatherBadgeLabels labels;
  final bool onDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!shouldShowWeatherPreview(
      lifecycle: TripLifecycle.parse(trip.lifecycle),
      startDateIso: trip.startDate,
      now: DateTime.now(),
    )) {
      return const SizedBox.shrink();
    }

    final previewAsync = ref.watch(weatherPreviewProvider(trip.id));
    return previewAsync.when(
      data: (preview) {
        if (preview == null) return const SizedBox.shrink();
        return WeatherBadge(
          preview: preview,
          labels: labels,
          onDark: onDark,
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

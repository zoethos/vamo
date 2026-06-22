import 'dart:io';

import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../capture/capture_providers.dart';
import '../expenses/expenses_providers.dart';
import '../places/place_geocode.dart';
import '../plan/plan_providers.dart';
import '../sync/trip_realtime_binding.dart';
import '../trips/trip_home_labels.dart';
import '../trips/trip_section_back_button.dart';
import '../trips/trips_models.dart';
import '../trips/trips_providers.dart';
import 'trip_map_labels.dart';
import 'trip_map_moments.dart';

/// OSM tile configuration, isolated so a keyed provider (MapTiler/Stadia/
/// self-hosted) can replace the public OSM tiles via one edit if beta usage
/// grows. Public OSM tiles are a shared, capacity-limited service — we send an
/// app-identifying User-Agent and rely on flutter_map's default (cache-honoring)
/// network provider; no bulk/offline prefetch and no no-cache headers.
abstract final class _TripMapTiles {
  static const urlTemplate = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static const userAgentPackageName = 'app.vamo';
  static const attribution = 'OpenStreetMap contributors';
  static final copyrightUri =
      Uri.parse('https://www.openstreetmap.org/copyright');
}

/// Geocoded coordinates for the trip destination, used to center the map before
/// any moments exist. Tolerates failure (web/no-network/no-match) by returning
/// null — the screen then falls back to a calm world view.
final tripDestinationCoordsProvider =
    FutureProvider.family<LatLng?, String>((ref, tripId) async {
  final detail = ref.watch(tripDetailProvider(tripId)).valueOrNull;
  final destination = detail?.destination?.trim();
  if (destination == null || destination.isEmpty) return null;
  final coords = await geocodeAddress(destination);
  return coords == null ? null : LatLng(coords.lat, coords.lng);
});

/// Always-on, progressive journey map. Renders from trip start (empty, centered
/// on the destination) and fills live as Visits, place-tagged expenses, and
/// geotagged photos land. Powers Trip Wrapped's data spine.
class TripMapScreen extends ConsumerStatefulWidget {
  const TripMapScreen({
    super.key,
    required this.tripId,
    required this.tripHomeLabels,
    this.mapLabels = const TripMapLabels(),
    this.tileProvider,
  });

  final String tripId;
  final TripHomeLabels tripHomeLabels;
  final TripMapLabels mapLabels;

  /// Overridable so tests run offline; production uses [NetworkTileProvider],
  /// which sends our app-identifying User-Agent and honors cache headers.
  final TileProvider? tileProvider;

  @override
  ConsumerState<TripMapScreen> createState() => _TripMapScreenState();
}

class _TripMapScreenState extends ConsumerState<TripMapScreen> {
  final MapController _mapController = MapController();

  /// null = "All days".
  int? _selectedDayIndex;
  String? _lastFitKey;

  TripMapLabels get _labels => widget.mapLabels;

  @override
  Widget build(BuildContext context) {
    ref.watch(tripRealtimeBindingProvider(widget.tripId));
    final trip = ref.watch(tripDetailProvider(widget.tripId));

    return trip.when(
      loading: () => _scaffold(
          _labels.title,
          const Center(
            child: CircularProgressIndicator(),
          )),
      error: (_, __) => _scaffold(
        _labels.title,
        AppErrorState(
          screen: 'trip_map',
          message: widget.tripHomeLabels.loadError,
          onRetry: () => ref.invalidate(tripDetailProvider(widget.tripId)),
        ),
      ),
      data: (detail) {
        if (detail == null) {
          return _scaffold(
            _labels.title,
            AppEmptyState(
              screen: 'trip_map',
              icon: Icons.map_outlined,
              title: widget.tripHomeLabels.notFoundTitle,
              subtitle: widget.tripHomeLabels.notFoundSubtitle,
            ),
          );
        }
        return _buildLoaded(context, detail);
      },
    );
  }

  Scaffold _scaffold(String title, Widget body, {List<Widget>? actions}) {
    return Scaffold(
      appBar: AppBar(
        leading: TripSectionBackButton(tripId: widget.tripId),
        title: Text(title),
        actions: actions,
      ),
      body: body,
    );
  }

  Widget _buildLoaded(BuildContext context, TripDetail detail) {
    final planItems =
        ref.watch(tripPlanItemsProvider(widget.tripId)).valueOrNull ?? const [];
    final expenses =
        ref.watch(tripExpensesProvider(widget.tripId)).valueOrNull ?? const [];
    final places =
        ref.watch(tripResolvedPlacesProvider(widget.tripId)).valueOrNull ??
            const [];
    final photos =
        ref.watch(tripPhotosProvider(widget.tripId)).valueOrNull ?? const [];
    final destCoords =
        ref.watch(tripDestinationCoordsProvider(widget.tripId)).valueOrNull;

    final allMoments = buildTripMapMoments(
      planItems: planItems,
      expenses: expenses,
      placesById: {for (final p in places) p.id: p},
      photos: photos,
    );

    final start = _parseDate(detail.startDate);
    final end = _parseDate(detail.endDate);
    final dayCount = tripDayCount(start, end);

    final visible = (_selectedDayIndex == null || start == null)
        ? allMoments
        : momentsForDay(
            allMoments,
            tripStart: start,
            dayIndex: _selectedDayIndex!,
          );

    // One camera fit per distinct (day, moment-set, destination) state, run
    // after layout so the map controller is attached. initialCenter already
    // gives a sensible first paint; this refines it as data/filters change.
    final fitKey = '$_selectedDayIndex'
        '|${visible.map((m) => m.id).join(',')}'
        '|$destCoords';
    if (fitKey != _lastFitKey) {
      _lastFitKey = fitKey;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _fitCamera(visible, destCoords),
      );
    }

    final initial = _initialCamera(allMoments, destCoords);
    final timed = [
      for (final m in visible)
        if (m.at != null) m
    ];

    return Scaffold(
      appBar: AppBar(
        leading: TripSectionBackButton(tripId: widget.tripId),
        title: Text(
          detail.destination?.isNotEmpty == true
              ? detail.destination!
              : _labels.title,
        ),
        actions: [
          if (allMoments.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.ios_share),
              tooltip: MaterialLocalizations.of(context).shareButtonLabel,
              onPressed: () => _share(detail),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: initial.center,
                    initialZoom: initial.zoom,
                    minZoom: 1,
                    maxZoom: 18,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: _TripMapTiles.urlTemplate,
                      userAgentPackageName: _TripMapTiles.userAgentPackageName,
                      tileProvider:
                          widget.tileProvider ?? NetworkTileProvider(),
                    ),
                    if (timed.length >= 2)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: [
                              for (final m in timed) LatLng(m.lat, m.lng),
                            ],
                            strokeWidth: 3,
                            color: VamoPlanTypeColors.train
                                .withValues(alpha: 0.65),
                          ),
                        ],
                      ),
                    MarkerLayer(
                      markers: [for (final m in visible) _marker(m)],
                    ),
                    RichAttributionWidget(
                      attributions: [
                        TextSourceAttribution(
                          _TripMapTiles.attribution,
                          onTap: _openOsmCopyright,
                        ),
                      ],
                    ),
                  ],
                ),
                if (visible.isEmpty) _EmptyOverlay(text: _labels.emptyOverlay),
              ],
            ),
          ),
          if (dayCount > 1)
            _DayScrubber(
              dayCount: dayCount,
              selectedDayIndex: _selectedDayIndex,
              labels: _labels,
              onSelected: (index) => setState(() => _selectedDayIndex = index),
            ),
        ],
      ),
    );
  }

  Marker _marker(MapMoment moment) {
    final visual = _visualFor(moment.kind);
    return Marker(
      point: LatLng(moment.lat, moment.lng),
      width: 38,
      height: 38,
      child: GestureDetector(
        onTap: () => _showMomentDetail(moment, visual),
        child: _MapPin(color: visual.color, icon: visual.icon),
      ),
    );
  }

  void _showMomentDetail(MapMoment moment, _MomentVisual visual) {
    final theme = Theme.of(context);
    final colors = context.vamoColors;
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: visual.color.withValues(alpha: 0.15),
                    child: Icon(visual.icon, color: visual.color, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _kindLabel(moment.kind),
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: colors.onSurfaceMuted),
                        ),
                        Text(
                          moment.title.isEmpty
                              ? _labels.untitledMoment
                              : moment.title,
                          style: theme.textTheme.titleMedium,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (moment.kind == MapMomentKind.memory &&
                  moment.thumbnailPath != null) ...[
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: AspectRatio(
                    aspectRatio: 16 / 10,
                    child: Image.file(
                      File(moment.thumbnailPath!),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          ColoredBox(color: colors.surfaceMuted),
                    ),
                  ),
                ),
              ],
              if (moment.at != null) ...[
                const SizedBox(height: 12),
                Text(
                  MaterialLocalizations.of(context)
                      .formatMediumDate(moment.at!.toLocal()),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: colors.onSurfaceMuted),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _kindLabel(MapMomentKind kind) => switch (kind) {
        MapMomentKind.visit => _labels.visitKind,
        MapMomentKind.expense => _labels.expenseKind,
        MapMomentKind.memory => _labels.memoryKind,
      };

  Future<void> _share(TripDetail detail) async {
    final where = detail.destination?.isNotEmpty == true
        ? detail.destination!
        : detail.name;
    try {
      await Share.share('Our $where trip map — Vamo');
    } catch (error, stackTrace) {
      reportAndLog(
        error,
        stackTrace,
        screen: 'trip_map',
        action: 'share_map',
        severity: ActionFailureSeverity.degraded,
        analytics: ref.read(analyticsProvider),
      );
    }
  }

  Future<void> _openOsmCopyright() async {
    try {
      await launchUrl(
        _TripMapTiles.copyrightUri,
        mode: LaunchMode.externalApplication,
      );
    } catch (error, stackTrace) {
      reportAndLog(
        error,
        stackTrace,
        screen: 'trip_map',
        action: 'open_osm_attribution',
        severity: ActionFailureSeverity.degraded,
        analytics: ref.read(analyticsProvider),
      );
    }
  }

  void _fitCamera(List<MapMoment> points, LatLng? fallback) {
    if (!mounted) return;
    try {
      if (points.isEmpty) {
        if (fallback != null) _mapController.move(fallback, 11);
        return;
      }
      if (points.length == 1) {
        _mapController.move(LatLng(points.first.lat, points.first.lng), 14);
        return;
      }
      final bounds = LatLngBounds.fromPoints(
        [for (final p in points) LatLng(p.lat, p.lng)],
      );
      _mapController.fitCamera(
        CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(48)),
      );
    } catch (error, stackTrace) {
      reportAndLog(
        error,
        stackTrace,
        screen: 'trip_map',
        action: 'fit_camera',
        severity: ActionFailureSeverity.degraded,
        analytics: ref.read(analyticsProvider),
      );
    }
  }

  _Camera _initialCamera(List<MapMoment> moments, LatLng? destCoords) {
    if (moments.isNotEmpty) {
      final lat =
          moments.map((m) => m.lat).reduce((a, b) => a + b) / moments.length;
      final lng =
          moments.map((m) => m.lng).reduce((a, b) => a + b) / moments.length;
      return _Camera(LatLng(lat, lng), moments.length == 1 ? 14 : 11);
    }
    if (destCoords != null) return _Camera(destCoords, 11);
    return const _Camera(LatLng(20, 0), 1.5); // calm world view
  }

  DateTime? _parseDate(String? iso) =>
      (iso == null || iso.isEmpty) ? null : DateTime.tryParse(iso);
}

class _Camera {
  const _Camera(this.center, this.zoom);
  final LatLng center;
  final double zoom;
}

class _MomentVisual {
  const _MomentVisual(this.color, this.icon);
  final Color color;
  final IconData icon;
}

// Marker hues reuse the shared plan-type palette so pins stay on-brand and
// dark-mode-safe (and avoid direct AppColors refs the ratchet caps): coral for
// visits, teal for place-tagged expenses, plum for geotagged memories.
_MomentVisual _visualFor(MapMomentKind kind) => switch (kind) {
      MapMomentKind.visit =>
        const _MomentVisual(VamoPlanTypeColors.visit, Icons.place),
      MapMomentKind.expense =>
        const _MomentVisual(VamoPlanTypeColors.train, Icons.receipt_long),
      MapMomentKind.memory =>
        const _MomentVisual(VamoPlanTypeColors.lodging, Icons.photo_camera),
    };

class _MapPin extends StatelessWidget {
  const _MapPin({required this.color, required this.icon});

  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.vamoColors;
    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: colors.surface, width: 2),
        boxShadow: [
          BoxShadow(
            color: colors.onSurface.withValues(alpha: 0.25),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Icon(icon, color: colors.surface, size: 18),
    );
  }
}

class _EmptyOverlay extends StatelessWidget {
  const _EmptyOverlay({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.vamoColors;
    return IgnorePointer(
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 32),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: colors.surface.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: colors.onSurface.withValues(alpha: 0.12),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.explore_outlined, color: colors.onSurfaceMuted),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  text,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: colors.onSurfaceMuted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DayScrubber extends StatelessWidget {
  const _DayScrubber({
    required this.dayCount,
    required this.selectedDayIndex,
    required this.labels,
    required this.onSelected,
  });

  final int dayCount;
  final int? selectedDayIndex;
  final TripMapLabels labels;
  final ValueChanged<int?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SizedBox(
        height: 56,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(labels.allDays),
                selected: selectedDayIndex == null,
                onSelected: (_) => onSelected(null),
              ),
            ),
            for (var i = 0; i < dayCount; i++)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(labels.dayLabel(i + 1, dayCount)),
                  selected: selectedDayIndex == i,
                  onSelected: (_) => onSelected(i),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

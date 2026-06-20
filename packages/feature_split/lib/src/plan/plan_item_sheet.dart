import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../places/place_geocode.dart';
import 'plan_event_rsvp_chips.dart';
import 'plan_labels.dart';
import 'plan_models.dart';
import 'plan_providers.dart';

class PlanItemSheet extends ConsumerStatefulWidget {
  const PlanItemSheet({
    super.key,
    required this.tripId,
    required this.labels,
    required this.existing,
    required this.readOnly,
    required this.onSave,
  });

  final String tripId;
  final PlanTabLabels labels;
  final PlanItemSummary? existing;
  final bool readOnly;
  final Future<void> Function(PlanItemInput input) onSave;

  @override
  ConsumerState<PlanItemSheet> createState() => _PlanItemSheetState();
}

class _PlanItemSheetState extends ConsumerState<PlanItemSheet> {
  late PlanItemKind _kind;
  late TextEditingController _title;
  late TextEditingController _notes;
  late TextEditingController _visitPlaceLabel;
  late TextEditingController _visitAddress;
  DateTime? _startsAt;
  DateTime? _endsAt;
  String? _dateRangeError;
  double? _visitLat;
  double? _visitLng;
  String? _visitPlaceId;
  String? _visitStatus;
  bool _visitStatusIsError = false;
  bool _geocoding = false;

  @override
  void initState() {
    super.initState();
    _kind = widget.existing?.kind ?? PlanItemKind.other;
    _title = TextEditingController(text: widget.existing?.title ?? '');
    _notes = TextEditingController(text: widget.existing?.notes ?? '');
    final visit = parseVisitPlaceMetadata(widget.existing?.metadata);
    _visitPlaceLabel = TextEditingController(
      text: visit?.placeLabel ??
          (widget.existing?.kind == PlanItemKind.visit
              ? widget.existing?.title ?? ''
              : ''),
    );
    _visitAddress = TextEditingController(text: visit?.address ?? '');
    _visitLat = visit?.lat;
    _visitLng = visit?.lng;
    _visitPlaceId = visit?.placeId;
    _startsAt = widget.existing?.startsAt;
    _endsAt = widget.existing?.endsAt;
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    _visitPlaceLabel.dispose();
    _visitAddress.dispose();
    super.dispose();
  }

  bool get _isActivity => _kind == PlanItemKind.activity;
  bool get _isVisit => _kind == PlanItemKind.visit;

  @override
  Widget build(BuildContext context) {
    final eventViews = _isActivity && widget.existing != null
        ? ref.watch(tripPlanEventViewsProvider(widget.tripId))
        : null;
    final eventView =
        widget.existing == null ? null : eventViews?[widget.existing!.id];
    final capabilities = ref.watch(planItemCapabilitiesProvider).valueOrNull ??
        PlanItemCapabilities.fallbackByKind();
    final visitCapabilities = capabilities[PlanItemKind.visit] ??
        PlanItemCapabilities.fallbackFor(PlanItemKind.visit);
    final tripPlaces = _isVisit && visitCapabilities.suggestsPois
        ? ref.watch(tripResolvedPlacesProvider(widget.tripId)).valueOrNull ??
            const <PlaceSummary>[]
        : const <PlaceSummary>[];

    return SafeArea(
      child: Padding(
        padding: EdgeInsetsDirectional.only(
          start: 16,
          end: 16,
          top: 16,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.existing == null
                    ? widget.labels.sheetTitleAdd
                    : widget.labels.sheetTitleEdit,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              InputDecorator(
                decoration: InputDecoration(labelText: widget.labels.fieldKind),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<PlanItemKind>(
                    value: _kind,
                    isExpanded: true,
                    items: PlanItemKind.values
                        .map(
                          (k) => DropdownMenuItem(
                            value: k,
                            child: Row(
                              children: [
                                Icon(k.icon, size: 20),
                                const SizedBox(width: 8),
                                Text(widget.labels.kindLabel(k)),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: widget.readOnly
                        ? null
                        : (v) => setState(() {
                              _kind = v ?? _kind;
                              if (_isVisit &&
                                  _visitPlaceLabel.text.trim().isEmpty) {
                                _visitPlaceLabel.text = _title.text.trim();
                              }
                            }),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _PlanKindBadge(kind: _kind, labels: widget.labels),
              const SizedBox(height: 8),
              TextField(
                controller: _title,
                readOnly: widget.readOnly,
                decoration:
                    InputDecoration(labelText: widget.labels.fieldTitle),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _notes,
                readOnly: widget.readOnly,
                maxLines: 3,
                decoration:
                    InputDecoration(labelText: widget.labels.fieldNotes),
              ),
              if (_isVisit) ...[
                const SizedBox(height: 12),
                _VisitDetailsSection(
                  labels: widget.labels,
                  places: tripPlaces,
                  readOnly: widget.readOnly,
                  placeLabelController: _visitPlaceLabel,
                  addressController: _visitAddress,
                  geocoding: _geocoding,
                  status: _visitStatus,
                  statusIsError: _visitStatusIsError,
                  hasCoords: _visitLat != null && _visitLng != null,
                  onPlaceSelected: _applyTripPlace,
                  onGeocode: _geocodeVisitAddress,
                ),
              ],
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(widget.labels.fieldStart),
                subtitle: Text(
                  _startsAt == null ? '—' : _startsAt!.toLocal().toString(),
                ),
                trailing: const Icon(Icons.calendar_today_outlined),
                onTap: widget.readOnly ? null : () => _pickDate(isStart: true),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(widget.labels.fieldEnd),
                subtitle: Text(
                  _endsAt == null ? '—' : _endsAt!.toLocal().toString(),
                ),
                trailing: const Icon(Icons.calendar_today_outlined),
                onTap: widget.readOnly ? null : () => _pickDate(isStart: false),
              ),
              if (_dateRangeError != null)
                Padding(
                  padding: const EdgeInsetsDirectional.only(top: 4),
                  child: Text(
                    _dateRangeError!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                  ),
                ),
              if (_isActivity &&
                  widget.existing != null &&
                  eventView != null) ...[
                const SizedBox(height: 12),
                Text(
                  widget.labels.eventRsvpSection,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 8),
                if (!eventView.counts.isEmpty)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(bottom: 8),
                    child: Text(
                      widget.labels.rsvpSummary(
                        eventView.counts.going,
                        eventView.counts.maybe,
                        eventView.counts.declined,
                      ),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.graphite,
                          ),
                    ),
                  ),
                PlanEventRsvpChips(
                  planItemId: widget.existing!.id,
                  labels: widget.labels,
                  myStatus: eventView.myStatus,
                  readOnly: widget.readOnly,
                ),
              ] else if (_isActivity && widget.existing == null) ...[
                const SizedBox(height: 12),
                Text(
                  widget.labels.eventRsvpHint,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.graphite,
                      ),
                ),
              ],
              const SizedBox(height: 12),
              if (!widget.readOnly)
                FilledButton(
                  onPressed: () async {
                    var title = _title.text.trim();
                    final metadata = _metadataForSave();
                    if (metadata == null) return;
                    if (_isVisit && title.isEmpty) {
                      title = _visitPlaceLabel.text.trim();
                    }
                    if (title.isEmpty) return;
                    _validateDateRange();
                    if (_dateRangeError != null) {
                      setState(() {});
                      return;
                    }
                    await widget.onSave(
                      PlanItemInput(
                        tripId: widget.tripId,
                        kind: _kind,
                        title: title,
                        notes: _notes.text.trim(),
                        startsAt: _startsAt,
                        endsAt: _endsAt,
                        metadata: metadata,
                      ),
                    );
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: Text(widget.labels.save),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Map<String, Object?>? _metadataForSave() {
    if (!_isVisit) {
      if (widget.existing != null && widget.existing!.kind == _kind) {
        return widget.existing!.metadata;
      }
      return const <String, Object?>{};
    }

    final placeLabel = _visitPlaceLabel.text.trim();
    if (placeLabel.isEmpty) {
      setState(() {
        _visitStatus = widget.labels.visitPlaceRequired;
        _visitStatusIsError = true;
      });
      return null;
    }

    return buildVisitPlaceMetadata(
      placeLabel: placeLabel,
      address: _visitAddress.text,
      lat: _visitLat,
      lng: _visitLng,
      placeId: _visitPlaceId,
    );
  }

  void _applyTripPlace(PlaceSummary place) {
    setState(() {
      _visitPlaceLabel.text = place.label;
      if (_title.text.trim().isEmpty) {
        _title.text = place.label;
      }
      _visitAddress.text = place.address ?? '';
      _visitLat = place.lat;
      _visitLng = place.lng;
      _visitPlaceId = place.id;
      _visitStatus = place.lat != null && place.lng != null
          ? widget.labels.visitCoordinatesSaved
          : null;
      _visitStatusIsError = false;
    });
  }

  Future<void> _geocodeVisitAddress() async {
    final address = _visitAddress.text.trim();
    if (address.isEmpty) {
      setState(() {
        _visitStatus = widget.labels.visitAddressRequiredForGeocode;
        _visitStatusIsError = true;
      });
      return;
    }

    setState(() {
      _geocoding = true;
      _visitStatus = null;
      _visitStatusIsError = false;
    });

    GeocodeCoords? coords;
    try {
      coords = await geocodeAddress(address);
    } catch (_) {
      coords = null;
    }
    if (!mounted) return;

    setState(() {
      _geocoding = false;
      if (coords == null) {
        _visitStatus = widget.labels.visitCoordinatesNotFound;
        _visitStatusIsError = true;
        return;
      }
      _visitLat = coords.lat;
      _visitLng = coords.lng;
      _visitPlaceId = null;
      _visitStatus = widget.labels.visitCoordinatesSaved;
      _visitStatusIsError = false;
    });
  }

  void _validateDateRange() {
    if (_startsAt != null && _endsAt != null && _endsAt!.isBefore(_startsAt!)) {
      _dateRangeError = widget.labels.endBeforeStart;
    } else {
      _dateRangeError = null;
    }
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = (isStart ? _startsAt : _endsAt) ?? DateTime.now();
    final result = await showVamoDatePicker(
      context: context,
      labels: VamoDatePickerLabels(
        cancel: widget.labels.datePickerCancel,
        skip: widget.labels.datePickerSkip,
        select: widget.labels.datePickerSelect,
      ),
      initialDate: initial,
      firstDate: isStart ? DateTime(2020) : (_startsAt ?? DateTime(2020)),
    );
    if (!mounted) return;
    if (result.outcome == VamoDatePickOutcome.cancelled) return;

    if (result.outcome == VamoDatePickOutcome.skipped) {
      setState(() {
        if (isStart) {
          _startsAt = null;
        } else {
          _endsAt = null;
        }
        _validateDateRange();
      });
      return;
    }

    final date = result.date!;
    if (!context.mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) {
      setState(() {
        if (isStart) {
          _startsAt = DateTime(date.year, date.month, date.day).toUtc();
        } else {
          _endsAt = DateTime(date.year, date.month, date.day).toUtc();
        }
        _validateDateRange();
      });
      return;
    }
    final combined = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    ).toUtc();
    setState(() {
      if (isStart) {
        _startsAt = combined;
      } else {
        _endsAt = combined;
      }
      _validateDateRange();
    });
  }
}

class _VisitDetailsSection extends StatelessWidget {
  const _VisitDetailsSection({
    required this.labels,
    required this.places,
    required this.readOnly,
    required this.placeLabelController,
    required this.addressController,
    required this.geocoding,
    required this.status,
    required this.statusIsError,
    required this.hasCoords,
    required this.onPlaceSelected,
    required this.onGeocode,
  });

  final PlanTabLabels labels;
  final List<PlaceSummary> places;
  final bool readOnly;
  final TextEditingController placeLabelController;
  final TextEditingController addressController;
  final bool geocoding;
  final String? status;
  final bool statusIsError;
  final bool hasCoords;
  final ValueChanged<PlaceSummary> onPlaceSelected;
  final VoidCallback onGeocode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          labels.visitSectionTitle,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        if (places.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            labels.visitFromTripPlaces,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final place in places.take(8))
                ActionChip(
                  avatar: const Icon(Icons.place_outlined, size: 16),
                  label: Text(place.label),
                  onPressed: readOnly ? null : () => onPlaceSelected(place),
                ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        TextField(
          controller: placeLabelController,
          readOnly: readOnly,
          decoration: InputDecoration(labelText: labels.visitPlaceLabel),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: addressController,
          readOnly: readOnly,
          decoration: InputDecoration(labelText: labels.visitAddressLabel),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: readOnly || geocoding ? null : onGeocode,
              icon: geocoding
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.my_location_outlined),
              label: Text(labels.visitFindCoordinates),
            ),
            const SizedBox(width: 8),
            if (hasCoords && status == null)
              Icon(
                Icons.check_circle_outline,
                size: 20,
                color: Theme.of(context).colorScheme.primary,
              ),
          ],
        ),
        if (status != null)
          Padding(
            padding: const EdgeInsetsDirectional.only(top: 4),
            child: Text(
              status!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: statusIsError
                    ? theme.colorScheme.error
                    : theme.colorScheme.primary,
              ),
            ),
          ),
      ],
    );
  }
}

class _PlanKindBadge extends StatelessWidget {
  const _PlanKindBadge({required this.kind, required this.labels});

  final PlanItemKind kind;
  final PlanTabLabels labels;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Chip(
        avatar: Icon(
          kind.icon,
          size: 18,
          color: AppColors.jadeTeal,
        ),
        label: Text(labels.kindLabel(kind)),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../places/place_geocode.dart';
import '../poi/poi_models.dart';
import '../poi/poi_providers.dart';
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
  late TextEditingController _transferOrigin;
  late TextEditingController _transferDestination;
  late TextEditingController _transferProvider;
  late TextEditingController _transferReference;
  DateTime? _startsAt;
  DateTime? _endsAt;
  String? _dateRangeError;
  TransferSubtype _transferSubtype = TransferSubtype.transit;
  double? _visitLat;
  double? _visitLng;
  String? _visitPlaceId;
  String? _visitStatus;
  bool _visitStatusIsError = false;
  bool _geocoding = false;
  bool _discoveringPois = false;
  List<PoiSummary> _poiSuggestions = const <PoiSummary>[];
  bool _poiGateVisible = false;

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
    final transfer = parseTransferMetadata(widget.existing?.metadata);
    _transferSubtype = transfer?.subtype ??
        legacyTransferSubtypeForKind(
            widget.existing?.kind ?? PlanItemKind.other) ??
        TransferSubtype.transit;
    _transferOrigin = TextEditingController(text: transfer?.origin ?? '');
    _transferDestination =
        TextEditingController(text: transfer?.destination ?? '');
    _transferProvider = TextEditingController(text: transfer?.provider ?? '');
    _transferReference = TextEditingController(text: transfer?.reference ?? '');
    _startsAt = widget.existing?.startsAt;
    _endsAt = widget.existing?.endsAt;
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    _visitPlaceLabel.dispose();
    _visitAddress.dispose();
    _transferOrigin.dispose();
    _transferDestination.dispose();
    _transferProvider.dispose();
    _transferReference.dispose();
    super.dispose();
  }

  bool get _isActivity => _kind == PlanItemKind.activity;
  bool get _isVisit => _kind == PlanItemKind.visit;
  bool get _isTransfer => _kind == PlanItemKind.transfer;

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
                              if (_isTransfer && _title.text.trim().isEmpty) {
                                _title.text = widget.labels
                                    .transferSubtype(_transferSubtype);
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
                  discoveringPois: _discoveringPois,
                  poiSuggestions: _poiSuggestions,
                  poiGateVisible: _poiGateVisible,
                  onPlaceSelected: _applyTripPlace,
                  onPoiSelected: _applyPoi,
                  onDiscoverPois: _discoverPois,
                ),
              ],
              if (_isTransfer) ...[
                const SizedBox(height: 12),
                _TransferDetailsSection(
                  labels: widget.labels,
                  readOnly: widget.readOnly,
                  subtype: _transferSubtype,
                  originController: _transferOrigin,
                  destinationController: _transferDestination,
                  providerController: _transferProvider,
                  referenceController: _transferReference,
                  onSubtypeChanged: (value) => setState(() {
                    _transferSubtype = value;
                    if (_title.text.trim().isEmpty) {
                      _title.text = widget.labels.transferSubtype(value);
                    }
                  }),
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
                    if (_isTransfer && title.isEmpty) {
                      title = widget.labels.transferSubtype(_transferSubtype);
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
    if (_isVisit) {
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

    if (_isTransfer) {
      return buildTransferMetadata(
        subtype: _transferSubtype,
        origin: _transferOrigin.text,
        destination: _transferDestination.text,
        provider: _transferProvider.text,
        reference: _transferReference.text,
      );
    }

    {
      if (widget.existing != null && widget.existing!.kind == _kind) {
        return widget.existing!.metadata;
      }
      return const <String, Object?>{};
    }
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

  void _applyPoi(PoiSummary poi) {
    final previousLabel = _visitPlaceLabel.text.trim();
    final currentTitle = _title.text.trim();
    setState(() {
      _visitPlaceLabel.text = poi.name;
      if (currentTitle.isEmpty || currentTitle == previousLabel) {
        _title.text = poi.name;
      }
      _visitAddress.text = poi.address ?? '';
      _visitLat = poi.lat;
      _visitLng = poi.lng;
      _visitPlaceId = poi.providerPlaceId;
      _visitStatus = widget.labels.visitCoordinatesSaved;
      _visitStatusIsError = false;
    });
  }

  Future<void> _discoverPois() async {
    if (_discoveringPois) return;

    setState(() {
      _discoveringPois = true;
      _poiGateVisible = false;
      _visitStatus = null;
      _visitStatusIsError = false;
    });

    var lat = _visitLat;
    var lng = _visitLng;
    if (lat == null || lng == null) {
      final query = _visitAddress.text.trim().isNotEmpty
          ? _visitAddress.text.trim()
          : _visitPlaceLabel.text.trim().isNotEmpty
              ? _visitPlaceLabel.text.trim()
              : _title.text.trim();

      if (query.isEmpty) {
        setState(() {
          _discoveringPois = false;
          _visitStatus = widget.labels.visitDiscoverNeedsPlace;
          _visitStatusIsError = true;
        });
        return;
      }

      setState(() {
        _geocoding = true;
        _visitStatus = widget.labels.visitDiscoverResolving;
        _visitStatusIsError = false;
      });

      final coords = await geocodeAddress(query);
      if (!mounted) return;
      if (coords == null) {
        setState(() {
          _discoveringPois = false;
          _geocoding = false;
          _visitStatus = widget.labels.visitCoordinatesNotFound;
          _visitStatusIsError = true;
        });
        return;
      }
      lat = coords.lat;
      lng = coords.lng;
      setState(() {
        _visitLat = lat;
        _visitLng = lng;
        _visitPlaceId = null;
        _geocoding = false;
        _visitStatus = null;
        _visitStatusIsError = false;
      });
    }

    final result = await ref.read(poiRepositoryProvider).discoverNearby(
          tripId: widget.tripId,
          lat: lat,
          lng: lng,
        );
    if (!mounted) return;

    setState(() {
      _discoveringPois = false;
      if (result == null) {
        _poiSuggestions = const <PoiSummary>[];
        _visitStatus = widget.labels.visitDiscoverLoadError;
        _visitStatusIsError = false;
        return;
      }
      if (result.gated) {
        _poiSuggestions = const <PoiSummary>[];
        _poiGateVisible = true;
        _visitStatus = null;
        _visitStatusIsError = false;
        return;
      }
      _poiSuggestions = result.pois;
      _visitStatus = result.isEmpty ? widget.labels.visitDiscoverEmpty : null;
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
    required this.discoveringPois,
    required this.poiSuggestions,
    required this.poiGateVisible,
    required this.onPlaceSelected,
    required this.onPoiSelected,
    required this.onDiscoverPois,
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
  final bool discoveringPois;
  final List<PoiSummary> poiSuggestions;
  final bool poiGateVisible;
  final ValueChanged<PlaceSummary> onPlaceSelected;
  final ValueChanged<PoiSummary> onPoiSelected;
  final VoidCallback onDiscoverPois;

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
          decoration: InputDecoration(
            labelText: labels.visitPlaceLabel,
            helperText: labels.visitPlaceHelper,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: addressController,
          readOnly: readOnly,
          decoration: InputDecoration(
            labelText: labels.visitAddressLabel,
            helperText: labels.visitAddressHelper,
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed:
              readOnly || discoveringPois || geocoding ? null : onDiscoverPois,
          icon: discoveringPois || geocoding
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.travel_explore_outlined),
          label: Text(labels.visitDiscoverNearby),
        ),
        Padding(
          padding: const EdgeInsetsDirectional.only(top: 4),
          child: Text(
            labels.visitDiscoverHelper,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        if (hasCoords && status == null)
          Padding(
            padding: const EdgeInsetsDirectional.only(top: 4),
            child: Icon(
              Icons.check_circle_outline,
              size: 20,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        if (poiGateVisible) ...[
          const SizedBox(height: 8),
          _PoiGateRow(message: labels.visitDiscoverGated),
        ],
        if (poiSuggestions.isNotEmpty) ...[
          const SizedBox(height: 8),
          Column(
            children: [
              for (final poi in poiSuggestions.take(5))
                _PoiSuggestionTile(
                  poi: poi,
                  readOnly: readOnly,
                  onTap: () => onPoiSelected(poi),
                ),
            ],
          ),
        ],
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

class _PoiGateRow extends StatelessWidget {
  const _PoiGateRow({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.jadeTeal.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.jadeTeal.withValues(alpha: 0.28)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            const Icon(Icons.lock_open_outlined, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }
}

class _PoiSuggestionTile extends StatelessWidget {
  const _PoiSuggestionTile({
    required this.poi,
    required this.readOnly,
    required this.onTap,
  });

  final PoiSummary poi;
  final bool readOnly;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final distance = poi.distanceM == null ? null : '${poi.distanceM} m';
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(poi.category.icon),
      title: Text(poi.name),
      subtitle: Text(
        [
          if (distance != null) distance,
          if (poi.address != null) poi.address!,
        ].join(' - '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: readOnly ? null : onTap,
    );
  }
}

class _TransferDetailsSection extends StatelessWidget {
  const _TransferDetailsSection({
    required this.labels,
    required this.readOnly,
    required this.subtype,
    required this.originController,
    required this.destinationController,
    required this.providerController,
    required this.referenceController,
    required this.onSubtypeChanged,
  });

  final PlanTabLabels labels;
  final bool readOnly;
  final TransferSubtype subtype;
  final TextEditingController originController;
  final TextEditingController destinationController;
  final TextEditingController providerController;
  final TextEditingController referenceController;
  final ValueChanged<TransferSubtype> onSubtypeChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          labels.transferSectionTitle,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        InputDecorator(
          decoration: InputDecoration(labelText: labels.transferSubtypeLabel),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<TransferSubtype>(
              value: subtype,
              isExpanded: true,
              items: TransferSubtype.values
                  .map(
                    (value) => DropdownMenuItem(
                      value: value,
                      child: Text(labels.transferSubtype(value)),
                    ),
                  )
                  .toList(),
              onChanged: readOnly
                  ? null
                  : (value) {
                      if (value != null) onSubtypeChanged(value);
                    },
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: originController,
          readOnly: readOnly,
          decoration: InputDecoration(labelText: labels.transferOriginLabel),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: destinationController,
          readOnly: readOnly,
          decoration:
              InputDecoration(labelText: labels.transferDestinationLabel),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: providerController,
          readOnly: readOnly,
          decoration: InputDecoration(labelText: labels.transferProviderLabel),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: referenceController,
          readOnly: readOnly,
          decoration: InputDecoration(labelText: labels.transferReferenceLabel),
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

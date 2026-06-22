import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../places/place_models.dart';
import '../poi/poi_models.dart';
import '../poi/poi_providers.dart';
import 'plan_event_rsvp_chips.dart';
import 'plan_labels.dart';
import 'plan_models.dart';
import 'plan_providers.dart';
import 'plan_type_visuals.dart';

const _visitSearchAccent = Color(0xFFC43628);

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
  late FocusNode _visitPlaceFocus;
  late FocusNode _visitAddressFocus;
  late TextEditingController _transferOrigin;
  late TextEditingController _transferDestination;
  late TextEditingController _transferProvider;
  late TextEditingController _transferReference;
  DateTime? _startsAt;
  DateTime? _endsAt;
  String? _dateRangeError;
  late bool _kindChosen;
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
  Timer? _visitSearchDebounce;
  int _visitSearchToken = 0;
  bool _suppressVisitSearch = false;
  late String _visitSearchSessionId;

  @override
  void initState() {
    super.initState();
    _kind = widget.existing?.kind ?? PlanItemKind.other;
    _kindChosen = widget.existing != null;
    _visitSearchSessionId = _newVisitSearchSessionId();
    _title = TextEditingController(text: widget.existing?.title ?? '');
    _title.addListener(_handleFormChanged);
    _notes = TextEditingController(text: widget.existing?.notes ?? '');
    final visit = parseVisitPlaceMetadata(widget.existing?.metadata);
    _visitPlaceLabel = TextEditingController(
      text: visit?.placeLabel ??
          (widget.existing?.kind == PlanItemKind.visit
              ? widget.existing?.title ?? ''
              : ''),
    );
    _visitAddress = TextEditingController(text: visit?.address ?? '');
    _visitPlaceFocus = FocusNode();
    _visitAddressFocus = FocusNode();
    _visitPlaceLabel.addListener(_scheduleVisitSearch);
    _visitAddress.addListener(_scheduleVisitSearch);
    _visitPlaceFocus.addListener(_handleVisitFocusChanged);
    _visitAddressFocus.addListener(_handleVisitFocusChanged);
    _visitLat = visit?.lat;
    _visitLng = visit?.lng;
    _visitPlaceId = visit?.placeId;
    final transfer = parseTransferMetadata(widget.existing?.metadata);
    _transferSubtype = transfer?.subtype ??
        legacyTransferSubtypeForKind(
          widget.existing?.kind ?? PlanItemKind.other,
        ) ??
        TransferSubtype.transit;
    _transferOrigin = TextEditingController(text: transfer?.origin ?? '');
    _transferDestination = TextEditingController(
      text: transfer?.destination ?? '',
    );
    _transferProvider = TextEditingController(text: transfer?.provider ?? '');
    _transferReference = TextEditingController(text: transfer?.reference ?? '');
    _startsAt = widget.existing?.startsAt;
    _endsAt = widget.existing?.endsAt;
  }

  @override
  void dispose() {
    _title.removeListener(_handleFormChanged);
    _title.dispose();
    _notes.dispose();
    _visitSearchDebounce?.cancel();
    _visitPlaceLabel.dispose();
    _visitAddress.dispose();
    _visitPlaceFocus.dispose();
    _visitAddressFocus.dispose();
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
    final colors = context.vamoColors;
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
        child: Stack(
          children: [
            SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      IconButton(
                        tooltip: widget.labels.cancelLabel,
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          widget.existing == null
                              ? widget.labels.addPlanItem
                              : widget.labels.sheetTitleEdit,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _PlanKindTileGrid(
                    labels: widget.labels,
                    selected: _kindChosen ? _kind : null,
                    readOnly: widget.readOnly ||
                        widget.existing?.kind == PlanItemKind.activity,
                    onSelected: _chooseKind,
                  ),
                  const SizedBox(height: 8),
                  if (widget.existing?.kind == PlanItemKind.activity) ...[
                    _PlanKindBadge(kind: _kind, labels: widget.labels),
                    const SizedBox(height: 8),
                  ],
                  if (_kindChosen && !_isVisit) ...[
                    TextField(
                      controller: _title,
                      readOnly: widget.readOnly,
                      decoration: InputDecoration(
                        labelText: widget.labels.fieldTitle,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (_kindChosen && _isVisit) ...[
                    const SizedBox(height: 12),
                    _VisitDetailsSection(
                      labels: widget.labels,
                      places: tripPlaces,
                      readOnly: widget.readOnly,
                      placeLabelController: _visitPlaceLabel,
                      addressController: _visitAddress,
                      placeFocusNode: _visitPlaceFocus,
                      addressFocusNode: _visitAddressFocus,
                      geocoding: _geocoding,
                      status: _visitStatus,
                      statusIsError: _visitStatusIsError,
                      hasCoords: _visitLat != null && _visitLng != null,
                      discoveringPois: _discoveringPois,
                      poiSuggestions: _poiSuggestions,
                      poiGateVisible: _poiGateVisible,
                      onPlaceSelected: _applyTripPlace,
                      onPoiSelected: _applyPoi,
                    ),
                    const SizedBox(height: 8),
                    _notesField(compact: true),
                  ],
                  if (_kindChosen && _isTransfer) ...[
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
                  if (_kindChosen && !_isVisit) ...[
                    const SizedBox(height: 8),
                    _notesField(compact: false),
                  ],
                  if (_kindChosen) ...[
                    const SizedBox(height: 8),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(widget.labels.fieldStart),
                      subtitle: Text(
                        _startsAt == null
                            ? '—'
                            : _startsAt!.toLocal().toString(),
                      ),
                      trailing: const Icon(Icons.calendar_today_outlined),
                      onTap: widget.readOnly
                          ? null
                          : () => _pickDate(isStart: true),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(widget.labels.fieldEnd),
                      subtitle: Text(
                        _endsAt == null ? '—' : _endsAt!.toLocal().toString(),
                      ),
                      trailing: const Icon(Icons.calendar_today_outlined),
                      onTap: widget.readOnly
                          ? null
                          : () => _pickDate(isStart: false),
                    ),
                  ],
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
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: colors.onSurfaceMuted),
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
                            color: colors.onSurfaceMuted,
                          ),
                    ),
                  ],
                  const SizedBox(height: 88),
                ],
              ),
            ),
            if (!widget.readOnly)
              PositionedDirectional(
                start: 0,
                end: 0,
                bottom: 0,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    boxShadow: [
                      BoxShadow(
                        color: colors.onSurface.withValues(alpha: 0.08),
                        blurRadius: 16,
                        offset: const Offset(0, -6),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(top: 10),
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: colors.action,
                        foregroundColor: colors.onAction,
                      ),
                      onPressed: _canSubmit ? _save : null,
                      child: Text(_ctaLabel),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  bool get _canSubmit {
    if (widget.readOnly || !_kindChosen) return false;
    if (_isVisit) return _visitPlaceLabel.text.trim().isNotEmpty;
    if (_isTransfer) return true;
    return _title.text.trim().isNotEmpty;
  }

  String get _ctaLabel {
    if (!_kindChosen) return widget.labels.ctaTapType;
    if (_isVisit && _visitPlaceLabel.text.trim().isEmpty) {
      return widget.labels.ctaTapPlace;
    }
    if (_isVisit && widget.existing == null) {
      return widget.labels.addKindLabel(_kind);
    }
    return widget.labels.save;
  }

  Widget _notesField({required bool compact}) {
    return TextField(
      controller: _notes,
      readOnly: widget.readOnly,
      maxLines: compact ? 1 : 3,
      decoration: InputDecoration(
        labelText: compact ? null : widget.labels.fieldNotes,
        hintText: compact ? widget.labels.fieldNoteHint : null,
        prefixIcon: compact ? const Icon(Icons.notes_outlined) : null,
        filled: compact,
        fillColor: compact
            ? Theme.of(context).colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.25,
                )
            : null,
        border: compact
            ? OutlineInputBorder(borderRadius: BorderRadius.circular(14))
            : null,
        enabledBorder: compact
            ? OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              )
            : null,
        focusedBorder: compact
            ? OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: _visitSearchAccent),
              )
            : null,
      ),
    );
  }

  void _chooseKind(PlanItemKind kind) {
    if (widget.readOnly) return;
    setState(() {
      _kind = kind;
      _kindChosen = true;
      _visitSearchDebounce?.cancel();
      _visitSearchSessionId = _newVisitSearchSessionId();
      _poiSuggestions = const <PoiSummary>[];
      _poiGateVisible = false;
      _visitStatus = null;
      _visitStatusIsError = false;
      if (_isVisit && _visitPlaceLabel.text.trim().isEmpty) {
        _visitPlaceLabel.text = _title.text.trim();
      }
      if (_isTransfer && _title.text.trim().isEmpty) {
        _title.text = widget.labels.transferSubtype(_transferSubtype);
      }
    });
  }

  Future<void> _save() async {
    if (!_canSubmit) return;
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
    if (mounted) Navigator.pop(context);
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
    _visitSearchDebounce?.cancel();
    setState(() {
      _suppressVisitSearch = true;
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
      _poiSuggestions = const <PoiSummary>[];
      _suppressVisitSearch = false;
    });
  }

  void _applyPoi(PoiSummary poi) {
    _visitSearchDebounce?.cancel();
    final previousLabel = _visitPlaceLabel.text.trim();
    final currentTitle = _title.text.trim();
    setState(() {
      _suppressVisitSearch = true;
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
      _poiSuggestions = const <PoiSummary>[];
      _suppressVisitSearch = false;
    });
  }

  void _handleVisitFocusChanged() {
    if (mounted) setState(() {});
  }

  void _handleFormChanged() {
    if (mounted) setState(() {});
  }

  void _scheduleVisitSearch() {
    if (_suppressVisitSearch || widget.readOnly || !_isVisit) return;
    _visitSearchDebounce?.cancel();
    _visitSearchToken++;
    final query = _visitSearchQuery();
    setState(() {
      _visitPlaceId = null;
      _visitLat = null;
      _visitLng = null;
      _poiGateVisible = false;
      _visitStatus = null;
      _visitStatusIsError = false;
      if (query.length < 3) {
        _poiSuggestions = const <PoiSummary>[];
        _discoveringPois = false;
        _geocoding = false;
      }
    });
    if (query.length < 3) return;
    _visitSearchDebounce = Timer(
      const Duration(milliseconds: 300),
      () => _searchPoisForVisit(showErrors: false),
    );
  }

  String _visitSearchQuery() {
    final place = _visitPlaceLabel.text.trim();
    if (place.isNotEmpty) return place;
    final address = _visitAddress.text.trim();
    if (address.isNotEmpty) return address;
    return _title.text.trim();
  }

  Future<void> _searchPoisForVisit({required bool showErrors}) async {
    _visitSearchDebounce?.cancel();
    final query = _visitSearchQuery();

    if (query.isEmpty || query.length < 3) {
      setState(() {
        _poiSuggestions = const <PoiSummary>[];
        _poiGateVisible = false;
        _visitStatus =
            showErrors ? widget.labels.visitDiscoverNeedsPlace : null;
        _visitStatusIsError = showErrors;
      });
      return;
    }

    final token = ++_visitSearchToken;

    setState(() {
      _discoveringPois = true;
      _geocoding = false;
      _poiGateVisible = false;
      _visitStatus = widget.labels.visitDiscoverResolving;
      _visitStatusIsError = false;
    });

    final result = await ref.read(poiRepositoryProvider).searchForTrip(
          tripId: widget.tripId,
          query: query,
          sessionId: _visitSearchSessionId,
        );
    if (!mounted || token != _visitSearchToken) return;

    setState(() {
      _discoveringPois = false;
      _geocoding = false;
      _visitPlaceId = null;
      if (result == null) {
        _poiSuggestions = const <PoiSummary>[];
        _visitStatus = showErrors ? widget.labels.visitDiscoverLoadError : null;
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

  String _newVisitSearchSessionId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${identityHashCode(this)}';

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
    required this.placeFocusNode,
    required this.addressFocusNode,
    required this.geocoding,
    required this.status,
    required this.statusIsError,
    required this.hasCoords,
    required this.discoveringPois,
    required this.poiSuggestions,
    required this.poiGateVisible,
    required this.onPlaceSelected,
    required this.onPoiSelected,
  });

  final PlanTabLabels labels;
  final List<PlaceSummary> places;
  final bool readOnly;
  final TextEditingController placeLabelController;
  final TextEditingController addressController;
  final FocusNode placeFocusNode;
  final FocusNode addressFocusNode;
  final bool geocoding;
  final String? status;
  final bool statusIsError;
  final bool hasCoords;
  final bool discoveringPois;
  final List<PoiSummary> poiSuggestions;
  final bool poiGateVisible;
  final ValueChanged<PlaceSummary> onPlaceSelected;
  final ValueChanged<PoiSummary> onPoiSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const accent = _visitSearchAccent;
    final hasQuery = placeLabelController.text.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                labels.visitPlaceLabel,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              labels.kindVisit,
              style: theme.textTheme.labelMedium?.copyWith(
                color: accent,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: placeLabelController,
          focusNode: placeFocusNode,
          readOnly: readOnly,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search_outlined),
            suffixIcon: hasQuery && !readOnly
                ? IconButton(
                    tooltip:
                        MaterialLocalizations.of(context).deleteButtonTooltip,
                    onPressed: () {
                      placeLabelController.clear();
                      placeFocusNode.requestFocus();
                    },
                    icon: const Icon(Icons.close),
                  )
                : null,
            hintText: labels.visitPlaceHelper,
            filled: true,
            fillColor: accent.withValues(alpha: 0.04),
            prefixIconColor: accent,
            suffixIconColor: accent.withValues(alpha: 0.55),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: accent, width: 1.4),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: accent.withValues(alpha: 0.55)),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
          ),
        ),
        if (discoveringPois) ...[
          const SizedBox(height: 8),
          Text(
            labels.visitDiscoverResolving,
            style: theme.textTheme.bodySmall?.copyWith(color: accent),
          ),
        ],
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
        ] else if (places.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            labels.visitFromTripPlaces,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Column(
            children: [
              for (final place in places.take(4))
                _TripPlaceSuggestionTile(
                  place: place,
                  readOnly: readOnly,
                  onTap: () => onPlaceSelected(place),
                ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        TextField(
          controller: addressController,
          focusNode: addressFocusNode,
          readOnly: readOnly,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.location_on_outlined),
            hintText: labels.visitAddressLabel,
            suffixText: labels.visitAddressOptionalLabel,
            filled: true,
            fillColor: addressFocusNode.hasFocus
                ? accent.withValues(alpha: 0.04)
                : theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.35,
                  ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: accent),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
          ),
        ),
        if (hasCoords && status == null)
          Padding(
            padding: const EdgeInsetsDirectional.only(top: 4),
            child: Icon(
              Icons.check_circle_outline,
              size: 20,
              color: accent,
            ),
          ),
        if (status != null)
          Padding(
            padding: const EdgeInsetsDirectional.only(top: 4),
            child: Text(
              status!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: statusIsError ? theme.colorScheme.error : accent,
              ),
            ),
          ),
      ],
    );
  }
}

class _PlanKindTileGrid extends StatelessWidget {
  const _PlanKindTileGrid({
    required this.labels,
    required this.selected,
    required this.readOnly,
    required this.onSelected,
  });

  static const _kinds = <PlanItemKind>[
    PlanItemKind.visit,
    PlanItemKind.train,
    PlanItemKind.flight,
    PlanItemKind.transfer,
    PlanItemKind.lodging,
    PlanItemKind.other,
  ];

  final PlanTabLabels labels;
  final PlanItemKind? selected;
  final bool readOnly;
  final ValueChanged<PlanItemKind> onSelected;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.08,
      children: [
        for (final kind in _kinds)
          _PlanKindTile(
            kind: kind,
            label: labels.kindLabel(kind),
            selected: selected == kind,
            readOnly: readOnly,
            onTap: () => onSelected(kind),
          ),
      ],
    );
  }
}

class _PlanKindTile extends StatelessWidget {
  const _PlanKindTile({
    required this.kind,
    required this.label,
    required this.selected,
    required this.readOnly,
    required this.onTap,
  });

  final PlanItemKind kind;
  final String label;
  final bool selected;
  final bool readOnly;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visual = visualForPlanKind(kind);
    final color = selected ? visual.accent : theme.colorScheme.onSurfaceVariant;
    return Material(
      color: selected
          ? visual.accent.withValues(alpha: 0.08)
          : theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? visual.accent : theme.colorScheme.outlineVariant,
          width: selected ? 1.4 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: readOnly ? null : onTap,
        child: Padding(
          padding: const EdgeInsetsDirectional.all(10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: selected ? visual.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(
                    visual.icon,
                    color: selected ? Colors.white : color,
                    size: 22,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: color,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PoiGateRow extends StatelessWidget {
  const _PoiGateRow({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.vamoColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.success.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.success.withValues(alpha: 0.28)),
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
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 6),
      child: Material(
        color: _visitSearchAccent.withValues(alpha: 0.06),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: _visitSearchAccent.withValues(alpha: 0.18)),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          dense: true,
          leading: CircleAvatar(
            radius: 17,
            backgroundColor: _visitSearchAccent.withValues(alpha: 0.14),
            child: Icon(
              poi.category.icon,
              size: 18,
              color: _visitSearchAccent,
            ),
          ),
          title: Text(poi.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            [
              if (distance != null) distance,
              if (poi.address != null) poi.address!,
            ].join(' - '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: const Icon(
            Icons.check_circle_outline,
            color: _visitSearchAccent,
          ),
          onTap: readOnly ? null : onTap,
        ),
      ),
    );
  }
}

class _TripPlaceSuggestionTile extends StatelessWidget {
  const _TripPlaceSuggestionTile({
    required this.place,
    required this.readOnly,
    required this.onTap,
  });

  final PlaceSummary place;
  final bool readOnly;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final detail = [
      if (place.address != null) place.address!,
      if (place.lat != null && place.lng != null) 'mapped',
    ].join(' - ');
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 6),
      child: Material(
        color: _visitSearchAccent.withValues(alpha: 0.04),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: _visitSearchAccent.withValues(alpha: 0.14)),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          dense: true,
          leading: CircleAvatar(
            radius: 17,
            backgroundColor: _visitSearchAccent.withValues(alpha: 0.12),
            child: const Icon(
              Icons.place_outlined,
              size: 18,
              color: _visitSearchAccent,
            ),
          ),
          title:
              Text(place.label, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: detail.isEmpty
              ? null
              : Text(detail, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: const Icon(
            Icons.check_circle_outline,
            color: _visitSearchAccent,
          ),
          onTap: readOnly ? null : onTap,
        ),
      ),
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
          decoration: InputDecoration(
            labelText: labels.transferDestinationLabel,
          ),
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
    final visual = visualForPlanKind(kind);
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Chip(
        avatar: Icon(visual.icon, size: 18, color: visual.accent),
        label: Text(labels.kindLabel(kind)),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

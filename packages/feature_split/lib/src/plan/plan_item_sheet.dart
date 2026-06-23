import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../places/place_models.dart';
import '../poi/place_info_card.dart';
import '../poi/poi_models.dart';
import '../poi/poi_providers.dart';
import '../shared/vamo_slidable_row.dart';
import 'plan_event_rsvp_chips.dart';
import 'plan_labels.dart';
import 'plan_models.dart';
import 'plan_providers.dart';
import 'plan_type_visuals.dart';

const _visitCoral = AppColors.sunsetCoral;
const _visitCoralText = AppColors.coralText;

class PlanItemSheet extends ConsumerStatefulWidget {
  const PlanItemSheet({
    super.key,
    required this.tripId,
    required this.labels,
    required this.existing,
    required this.readOnly,
    this.tripDateBounds = const TripPlanDateBounds(),
    required this.onSave,
  });

  final String tripId;
  final PlanTabLabels labels;
  final PlanItemSummary? existing;
  final bool readOnly;
  final TripPlanDateBounds tripDateBounds;
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
  PoiSummary? _selectedPoi;
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
                  Text(
                    widget.existing == null
                        ? widget.labels.sheetTitleAdd
                        : widget.labels.sheetTitleEdit,
                    style: Theme.of(context).textTheme.titleLarge,
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
                  if (_kindChosen && !_isVisit)
                    TextField(
                      controller: _notes,
                      readOnly: widget.readOnly,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: widget.labels.fieldNotes,
                      ),
                    ),
                  if (_kindChosen && _isVisit) ...[
                    const SizedBox(height: 12),
                    _VisitDetailsSection(
                      labels: widget.labels,
                      places: tripPlaces,
                      readOnly: widget.readOnly,
                      placeLabelController: _visitPlaceLabel,
                      addressController: _visitAddress,
                      notesController: _notes,
                      placeFocusNode: _visitPlaceFocus,
                      addressFocusNode: _visitAddressFocus,
                      geocoding: _geocoding,
                      status: _visitStatus,
                      statusIsError: _visitStatusIsError,
                      hasCoords: _visitLat != null && _visitLng != null,
                      discoveringPois: _discoveringPois,
                      poiSuggestions: _poiSuggestions,
                      poiGateVisible: _poiGateVisible,
                      selectedPlaceId: _visitPlaceId,
                      onPlaceSelected: _applyTripPlace,
                      onPoiSelected: _applyPoi,
                      onClearSearch: _clearVisitSearch,
                    ),
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
                              ?.copyWith(color: AppColors.graphite),
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
                        color: AppColors.ink.withValues(alpha: 0.08),
                        blurRadius: 16,
                        offset: const Offset(0, -6),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(top: 10),
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.goLime,
                        foregroundColor: AppColors.ink,
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
    if (_isVisit) return widget.labels.visitSave;
    return widget.labels.save;
  }

  void _clearVisitSearch() {
    setState(() {
      _visitSearchDebounce?.cancel();
      _poiSuggestions = const <PoiSummary>[];
      _poiGateVisible = false;
      _visitPlaceId = null;
      _visitLat = null;
      _visitLng = null;
      _selectedPoi = null;
      _visitStatus = null;
      _visitStatusIsError = false;
      _discoveringPois = false;
    });
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
        photoUrl: _selectedPoi?.photoUrl,
        category: _selectedPoi?.category.name,
        rating: _selectedPoi?.rating,
        price: _selectedPoi?.priceLevel,
        website: _selectedPoi?.website,
        phone: _selectedPoi?.phone,
        hours: _selectedPoi?.hours,
        about: _selectedPoi?.about,
        aboutSource: _selectedPoi?.about == null ? null : 'foursquare',
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
      _selectedPoi = null;
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
      _selectedPoi = poi;
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
      _selectedPoi = null;
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
      _selectedPoi = null;
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
    _dateRangeError = switch (validatePlanItemDates(
      startsAt: _startsAt,
      endsAt: _endsAt,
      bounds: widget.tripDateBounds,
    )) {
      PlanDateValidationFailure.endBeforeStart => widget.labels.endBeforeStart,
      PlanDateValidationFailure.outsideTripRange =>
        widget.labels.dateOutsideTripRange,
      null => null,
    };
  }

  Future<void> _pickDate({required bool isStart}) async {
    final first = _firstSelectableDate(isStart: isStart);
    final last = widget.tripDateBounds.endDay ?? DateTime(2100);
    final selectedDate = (isStart ? _startsAt : _endsAt) ?? DateTime.now();
    var initial = planDayForDateTime(selectedDate);
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(last)) initial = last;
    final result = await showVamoDatePicker(
      context: context,
      labels: VamoDatePickerLabels(
        cancel: widget.labels.datePickerCancel,
        skip: widget.labels.datePickerSkip,
        select: widget.labels.datePickerSelect,
      ),
      initialDate: initial,
      firstDate: first.isAfter(last) ? last : first,
      lastDate: last,
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
      initialTime: TimeOfDay.fromDateTime(selectedDate),
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

  DateTime _firstSelectableDate({required bool isStart}) {
    var first = widget.tripDateBounds.startDay ?? DateTime(2020);
    if (!isStart && _startsAt != null) {
      final startDay = planDayForDateTime(_startsAt!);
      if (startDay.isAfter(first)) first = startDay;
    }
    return first;
  }
}

class _VisitDetailsSection extends StatefulWidget {
  const _VisitDetailsSection({
    required this.labels,
    required this.places,
    required this.readOnly,
    required this.placeLabelController,
    required this.addressController,
    required this.notesController,
    required this.placeFocusNode,
    required this.addressFocusNode,
    required this.geocoding,
    required this.status,
    required this.statusIsError,
    required this.hasCoords,
    required this.discoveringPois,
    required this.poiSuggestions,
    required this.poiGateVisible,
    required this.selectedPlaceId,
    required this.onPlaceSelected,
    required this.onPoiSelected,
    required this.onClearSearch,
  });

  final PlanTabLabels labels;
  final List<PlaceSummary> places;
  final bool readOnly;
  final TextEditingController placeLabelController;
  final TextEditingController addressController;
  final TextEditingController notesController;
  final FocusNode placeFocusNode;
  final FocusNode addressFocusNode;
  final bool geocoding;
  final String? status;
  final bool statusIsError;
  final bool hasCoords;
  final bool discoveringPois;
  final List<PoiSummary> poiSuggestions;
  final bool poiGateVisible;
  final String? selectedPlaceId;
  final ValueChanged<PlaceSummary> onPlaceSelected;
  final ValueChanged<PoiSummary> onPoiSelected;
  final VoidCallback onClearSearch;

  @override
  State<_VisitDetailsSection> createState() => _VisitDetailsSectionState();
}

class _VisitDetailsSectionState extends State<_VisitDetailsSection> {
  late bool _notesExpanded;

  @override
  void initState() {
    super.initState();
    _notesExpanded = widget.notesController.text.trim().isNotEmpty;
    widget.placeLabelController.addListener(_rebuild);
    widget.placeFocusNode.addListener(_rebuild);
  }

  @override
  void didUpdateWidget(covariant _VisitDetailsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.placeLabelController != widget.placeLabelController) {
      oldWidget.placeLabelController.removeListener(_rebuild);
      widget.placeLabelController.addListener(_rebuild);
    }
    if (oldWidget.placeFocusNode != widget.placeFocusNode) {
      oldWidget.placeFocusNode.removeListener(_rebuild);
      widget.placeFocusNode.addListener(_rebuild);
    }
  }

  @override
  void dispose() {
    widget.placeLabelController.removeListener(_rebuild);
    widget.placeFocusNode.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  void _clearSearch() {
    widget.placeLabelController.clear();
    widget.onClearSearch();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shape = context.vamoShape;
    final query = widget.placeLabelController.text.trim();
    final showEmptyState = !widget.discoveringPois &&
        !widget.poiGateVisible &&
        query.length >= 3 &&
        widget.poiSuggestions.isEmpty &&
        widget.status == widget.labels.visitDiscoverEmpty;
    final showErrorStatus = widget.status != null &&
        widget.statusIsError &&
        widget.status != widget.labels.visitDiscoverResolving;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              widget.labels.visitPlaceLabel,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(width: 8),
            DecoratedBox(
              decoration: BoxDecoration(
                color: _visitCoral.withValues(alpha: 0.12),
                borderRadius: shape.chipBorderRadius,
              ),
              child: Padding(
                padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                child: Text(
                  widget.labels.kindVisit,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: _visitCoralText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
        if (widget.places.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            widget.labels.visitFromTripPlaces,
            style: theme.textTheme.labelMedium?.copyWith(
              color: AppColors.graphite,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final place in widget.places.take(8))
                ActionChip(
                  avatar: Icon(
                    Icons.place_outlined,
                    size: 16,
                    color: widget.selectedPlaceId == place.id
                        ? _visitCoralText
                        : AppColors.graphite,
                  ),
                  label: Text(place.label),
                  backgroundColor: widget.selectedPlaceId == place.id
                      ? _visitCoral.withValues(alpha: 0.12)
                      : null,
                  side: widget.selectedPlaceId == place.id
                      ? BorderSide(color: _visitCoral)
                      : null,
                  onPressed: widget.readOnly
                      ? null
                      : () => widget.onPlaceSelected(place),
                ),
            ],
          ),
        ],
        const SizedBox(height: 10),
        TextField(
          key: const Key('visitPlaceSearchField'),
          controller: widget.placeLabelController,
          focusNode: widget.placeFocusNode,
          readOnly: widget.readOnly,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: widget.labels.visitPlaceHelper,
            prefixIcon: const Icon(Icons.search, color: _visitCoral),
            suffixIcon:
                widget.placeLabelController.text.isNotEmpty && !widget.readOnly
                    ? IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        color: AppColors.graphite,
                        onPressed: _clearSearch,
                      )
                    : null,
            filled: true,
            fillColor: context.vamoColors.surface,
            contentPadding: const EdgeInsetsDirectional.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(999),
              borderSide: BorderSide(
                color: AppColors.graphite.withValues(alpha: 0.22),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(999),
              borderSide: const BorderSide(color: _visitCoral, width: 1.5),
            ),
          ),
        ),
        if (widget.discoveringPois) ...[
          const SizedBox(height: 10),
          const Align(
            alignment: AlignmentDirectional.centerStart,
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: _visitCoral,
              ),
            ),
          ),
        ],
        if (widget.poiGateVisible) ...[
          const SizedBox(height: 10),
          _PoiGateRow(message: widget.labels.visitDiscoverGated),
        ],
        if (widget.poiSuggestions.isNotEmpty) ...[
          const SizedBox(height: 8),
          DecoratedBox(
            decoration: BoxDecoration(
              color: context.vamoColors.surface,
              borderRadius: shape.cardBorderRadius,
              border: Border.all(
                color: AppColors.graphite.withValues(alpha: 0.15),
              ),
            ),
            child: Column(
              children: [
                for (var i = 0;
                    i < widget.poiSuggestions.take(5).length;
                    i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      thickness: 1,
                      color: AppColors.graphite.withValues(alpha: 0.12),
                    ),
                  _VisitPoiSuggestionRow(
                    poi: widget.poiSuggestions[i],
                    selected: widget.selectedPlaceId != null &&
                        widget.selectedPlaceId ==
                            widget.poiSuggestions[i].providerPlaceId,
                    readOnly: widget.readOnly,
                    onTap: () => widget.onPoiSelected(widget.poiSuggestions[i]),
                  ),
                ],
              ],
            ),
          ),
        ],
        if (showEmptyState) ...[
          const SizedBox(height: 10),
          Text(
            widget.labels.visitDiscoverEmpty,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.graphite,
            ),
          ),
        ],
        if (showErrorStatus)
          Padding(
            padding: const EdgeInsetsDirectional.only(top: 8),
            child: Text(
              widget.status!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        if (widget.hasCoords &&
            widget.status == widget.labels.visitCoordinatesSaved)
          Padding(
            padding: const EdgeInsetsDirectional.only(top: 8),
            child: Row(
              children: [
                const Icon(
                  Icons.check_circle_outline,
                  size: 18,
                  color: _visitCoral,
                ),
                const SizedBox(width: 6),
                Text(
                  widget.status!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.graphite,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('visitAddressField'),
          controller: widget.addressController,
          focusNode: widget.addressFocusNode,
          readOnly: widget.readOnly,
          decoration: InputDecoration(
            prefixIcon: const Icon(
              Icons.location_on_outlined,
              color: AppColors.graphite,
            ),
            labelText:
                '${widget.labels.visitAddressLabel} (${widget.labels.visitAddressHelper})',
            enabledBorder: OutlineInputBorder(
              borderRadius: shape.controlBorderRadius,
              borderSide: BorderSide(
                color: AppColors.graphite.withValues(alpha: 0.22),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: shape.controlBorderRadius,
              borderSide: const BorderSide(color: _visitCoral),
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_notesExpanded)
          TextField(
            key: const Key('visitNotesField'),
            controller: widget.notesController,
            readOnly: widget.readOnly,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: widget.labels.fieldNotes,
              enabledBorder: OutlineInputBorder(
                borderRadius: shape.controlBorderRadius,
                borderSide: BorderSide(
                  color: AppColors.graphite.withValues(alpha: 0.22),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: shape.controlBorderRadius,
                borderSide: const BorderSide(color: _visitCoral),
              ),
            ),
          )
        else
          InkWell(
            key: const Key('visitAddNoteRow'),
            onTap: widget.readOnly
                ? null
                : () => setState(() => _notesExpanded = true),
            borderRadius: shape.controlBorderRadius,
            child: Padding(
              padding: const EdgeInsetsDirectional.symmetric(vertical: 10),
              child: Text(
                widget.labels.visitAddNote,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.graphite,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _VisitPoiSuggestionRow extends StatelessWidget {
  const _VisitPoiSuggestionRow({
    required this.poi,
    required this.selected,
    required this.readOnly,
    required this.onTap,
  });

  final PoiSummary poi;
  final bool selected;
  final bool readOnly;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitleParts = <String>[
      _categoryLabel(poi.category),
      if (_locality(poi.address) case final locality?) locality,
      if (poi.distanceM case final distance?) '${distance} m',
    ];

    final row = Material(
      color:
          selected ? _visitCoral.withValues(alpha: 0.10) : Colors.transparent,
      child: InkWell(
        onTap: readOnly ? null : onTap,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 12, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsetsDirectional.only(top: 2),
                child: Icon(Icons.place_outlined, size: 20, color: _visitCoral),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      poi.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    if (subtitleParts.isNotEmpty)
                      Text(
                        subtitleParts.join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.graphite,
                        ),
                      ),
                  ],
                ),
              ),
              if (selected)
                const Icon(Icons.check_circle, size: 20, color: _visitCoral),
            ],
          ),
        ),
      ),
    );
    return VamoSlidableRow(
      infoLabel: 'Info',
      onInfo: () => showPlaceInfoCard(
        context,
        info: PlaceInfo.fromPoi(poi),
      ),
      child: row,
    );
  }

  static String _categoryLabel(PoiCategory category) {
    final raw = category.name;
    return raw[0].toUpperCase() + raw.substring(1);
  }

  static String? _locality(String? address) {
    if (address == null || address.trim().isEmpty) return null;
    final parts = address.split(',').map((part) => part.trim()).toList();
    if (parts.length >= 2) return parts[parts.length - 2];
    return parts.last;
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
    final color = selected ? visual.accent : AppColors.graphite;
    return Material(
      color: selected
          ? visual.accent.withValues(alpha: 0.1)
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
              Icon(visual.icon, color: color),
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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _visitCoral.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _visitCoral.withValues(alpha: 0.28)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            const Icon(Icons.lock_open_outlined, size: 18, color: _visitCoral),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppColors.graphite),
              ),
            ),
          ],
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

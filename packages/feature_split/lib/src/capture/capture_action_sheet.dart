import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../signals/coming_soon_sheet.dart';
import '../trips/trips_repository.dart';
import 'capture_repository.dart';

const _captureFlyoutOverlayKey =
    ValueKey<String>('capture-action-flyout-overlay');

/// Compact capture choices (S30 / S44 carousel), shown as a hero-anchored flyout.
Future<void> showCaptureActionSheet({
  required BuildContext context,
  required String tripId,
  LayerLink? anchorLink,
}) {
  final overlay = Overlay.of(context, rootOverlay: true);
  final completer = Completer<void>();
  late final OverlayEntry entry;

  void removeEntry() {
    if (entry.mounted) entry.remove();
    if (!completer.isCompleted) completer.complete();
  }

  entry = OverlayEntry(
    builder: (_) => _CaptureFlyoutOverlay(
      anchorLink: anchorLink,
      routeContext: context,
      tripId: tripId,
      onRemove: removeEntry,
    ),
  );

  overlay.insert(entry);
  return completer.future;
}

class _CaptureFlyoutOverlay extends StatefulWidget {
  const _CaptureFlyoutOverlay({
    required this.anchorLink,
    required this.routeContext,
    required this.tripId,
    required this.onRemove,
  });

  final LayerLink? anchorLink;
  final BuildContext routeContext;
  final String tripId;
  final VoidCallback onRemove;

  @override
  State<_CaptureFlyoutOverlay> createState() => _CaptureFlyoutOverlayState();
}

class _CaptureFlyoutOverlayState extends State<_CaptureFlyoutOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _scale;
  late final Animation<Offset> _slide;
  var _closing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 170),
      reverseDuration: const Duration(milliseconds: 110),
    );
    final curve = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _fade = curve;
    _scale = Tween<double>(begin: 0.86, end: 1).animate(curve);
    _slide = Tween<Offset>(
      begin: const Offset(0.08, -0.08),
      end: Offset.zero,
    ).animate(curve);
    unawaited(_controller.forward());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _dismiss() async {
    if (_closing) return;
    _closing = true;
    try {
      await _controller.reverse();
    } finally {
      widget.onRemove();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final alignment = isRtl ? Alignment.topLeft : Alignment.topRight;
    final offset = Offset(isRtl ? -24 : 24, 8);
    final flyout = FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: ScaleTransition(
          scale: _scale,
          alignment: alignment,
          child: CaptureChoiceSheet(
            tripId: widget.tripId,
            navigationContext: widget.routeContext,
            onDismiss: _dismiss,
          ),
        ),
      ),
    );

    return Material(
      key: _captureFlyoutOverlayKey,
      type: MaterialType.transparency,
      child: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => unawaited(_dismiss()),
            child: const SizedBox.expand(),
          ),
          if (widget.anchorLink != null)
            CompositedTransformFollower(
              link: widget.anchorLink!,
              showWhenUnlinked: false,
              targetAnchor: Alignment.bottomCenter,
              followerAnchor: alignment,
              offset: offset,
              child: Align(
                alignment: alignment,
                widthFactor: 1,
                heightFactor: 1,
                child: flyout,
              ),
            )
          else
            PositionedDirectional(
              top: MediaQuery.paddingOf(context).top + kToolbarHeight + 8,
              end: 16,
              child: flyout,
            ),
        ],
      ),
    );
  }
}

/// Test override for [ImagePicker.pickImage] — production uses [ImagePicker].
typedef CapturePickImage = Future<XFile?> Function({
  required ImageSource source,
  double? maxWidth,
  double? maxHeight,
  int? imageQuality,
});

class CaptureChoiceSheet extends ConsumerStatefulWidget {
  const CaptureChoiceSheet({
    super.key,
    required this.tripId,
    this.navigationContext,
    this.onDismiss,
    @visibleForTesting this.pickImage,
  });

  final String tripId;
  final BuildContext? navigationContext;
  final Future<void> Function()? onDismiss;

  @visibleForTesting
  final CapturePickImage? pickImage;

  @override
  ConsumerState<CaptureChoiceSheet> createState() => _CaptureChoiceSheetState();
}

class _CaptureChoiceSheetState extends ConsumerState<CaptureChoiceSheet> {
  static const _flyoutWidth = _CaptureCarouselMetrics.flyoutWidth;
  static const _flyoutHeight = _CaptureCarouselMetrics.flyoutHeight;
  static const _wheelItemExtent = _CaptureCarouselMetrics.wheelItemExtent;

  final _picker = ImagePicker();
  late final FixedExtentScrollController _wheelController;
  var _selectedIndex = 0;
  var _scrollIndex = 0.0;
  _CaptureChoice? _busy;

  static const _itemCount = 4;

  @override
  void initState() {
    super.initState();
    _wheelController = FixedExtentScrollController();
    _wheelController.addListener(_syncWheelScroll);
  }

  @override
  void dispose() {
    _wheelController.removeListener(_syncWheelScroll);
    _wheelController.dispose();
    super.dispose();
  }

  void _syncWheelScroll() {
    if (!_wheelController.hasClients) return;
    final next = _wheelController.offset / _wheelItemExtent;
    final index = next.round().clamp(0, _itemCount - 1);
    if ((next - _scrollIndex).abs() > 0.001 || index != _selectedIndex) {
      setState(() {
        _scrollIndex = next;
        _selectedIndex = index;
      });
    }
  }

  double _centerFocusFor(int index) {
    final distance = (_scrollIndex - index).abs();
    if (distance >= 1) return 0;
    return (1 - distance).clamp(0.0, 1.0);
  }

  double get _centerLabelOpacity {
    final frac = _scrollIndex - _scrollIndex.roundToDouble();
    return (1 - frac.abs() * 2).clamp(0.0, 1.0);
  }

  double get _centerLabelScale => 0.92 + 0.08 * _centerLabelOpacity;

  Future<void> _dismiss() async {
    final onDismiss = widget.onDismiss;
    if (onDismiss != null) {
      await onDismiss();
      return;
    }
    if (Navigator.of(context).canPop()) {
      Navigator.pop(context);
    }
  }

  Future<void> _addNote() async {
    final routeContext = widget.navigationContext ?? context;
    await _dismiss();
    if (!routeContext.mounted) return;
    await routeContext.push(AppRoutes.tripAddCaptureNote(widget.tripId));
  }

  Future<XFile?> _pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
  }) {
    final override = widget.pickImage;
    if (override != null) {
      return override(
        source: source,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        imageQuality: imageQuality,
      );
    }
    return _picker.pickImage(
      source: source,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      imageQuality: imageQuality,
    );
  }

  Future<void> _addPhoto() async {
    final picked = await _pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 80,
    );
    if (picked == null || !mounted) return;

    setState(() => _busy = _CaptureChoice.photo);
    try {
      await ref.read(captureRepositoryProvider).addPhoto(
            tripId: widget.tripId,
            sourcePath: picked.path,
          );
      if (!mounted) return;
      await _dismiss();
    } catch (e) {
      final routeContext = widget.navigationContext ?? context;
      if (!routeContext.mounted) return;
      showActionError(
        routeContext,
        ref,
        screen: 'trip_home',
        action: 'add_capture_photo',
        error: e,
      );
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _setBackground() async {
    try {
      final picked = await _pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );
      if (picked == null || !mounted) return;
      setState(() => _busy = _CaptureChoice.background);
      await ref.read(tripsRepositoryProvider).setTripBackground(
            tripId: widget.tripId,
            sourcePath: picked.path,
          );
      if (!mounted) return;
      await _dismiss();
    } catch (e, st) {
      debugPrint('SET-BG-FAIL [trip_home/set_trip_background]: $e\n$st');
      final routeContext = widget.navigationContext ?? context;
      if (!routeContext.mounted) return;
      showActionError(
        routeContext,
        ref,
        screen: 'trip_home',
        action: 'set_trip_background',
        error: e,
        stackTrace: st,
      );
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _addVideo() async {
    final picked = await _picker.pickVideo(source: ImageSource.gallery);
    if (picked == null || !mounted) return;
    final routeContext = widget.navigationContext ?? context;
    await _dismiss();
    if (!routeContext.mounted) return;
    await showComingSoonSheet(
      context: routeContext,
      ref: ref,
      interestEvent: VamoEvent.recapInterestTapped,
      feature: 'capture_video',
      title: 'Trip videos',
      description:
          'Short video memories from your trip will land here in a later wave.',
    );
  }

  List<_CaptureChoiceItem> _items() => [
        _CaptureChoiceItem(
          choice: _CaptureChoice.photo,
          icon: Icons.photo_camera_rounded,
          label: 'Photo',
          onTap: _addPhoto,
        ),
        _CaptureChoiceItem(
          choice: _CaptureChoice.video,
          icon: Icons.videocam_rounded,
          label: 'Video',
          onTap: _addVideo,
        ),
        _CaptureChoiceItem(
          choice: _CaptureChoice.note,
          icon: Icons.edit_note_rounded,
          label: 'Note',
          onTap: _addNote,
        ),
        _CaptureChoiceItem(
          choice: _CaptureChoice.background,
          icon: Icons.wallpaper_rounded,
          label: 'Background',
          onTap: _setBackground,
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final colors = context.vamoColors;
    final type = context.vamoType;
    final space = context.vamoSpace;
    final items = _items();
    final previousItem = _selectedIndex > 0 ? items[_selectedIndex - 1] : null;
    final nextItem =
        _selectedIndex < items.length - 1 ? items[_selectedIndex + 1] : null;
    final labelIndex = _scrollIndex.round().clamp(0, items.length - 1);

    return SizedBox(
      width: _flyoutWidth,
      height: _flyoutHeight,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_flyoutWidth / 2),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white.withValues(
                alpha: _CaptureCarouselMetrics.pillFillAlpha,
              ),
              borderRadius: BorderRadius.circular(_flyoutWidth / 2),
              border: Border.all(
                color: Colors.white.withValues(
                  alpha: _CaptureCarouselMetrics.pillBorderAlpha,
                ),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: space.x2),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: IgnorePointer(
                      child: _CaptureWheelNeighbors(
                        previous: previousItem,
                        next: nextItem,
                        colors: colors,
                        busy: _busy,
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: ListWheelScrollView.useDelegate(
                      controller: _wheelController,
                      physics: const FixedExtentScrollPhysics(),
                      itemExtent: _wheelItemExtent,
                      diameterRatio: 2.6,
                      perspective: 0.003,
                      squeeze: 0.68,
                      useMagnifier: true,
                      magnification: 1.6,
                      overAndUnderCenterOpacity: 0.9,
                      renderChildrenOutsideViewport: true,
                      clipBehavior: Clip.none,
                      onSelectedItemChanged: (index) {
                        setState(() => _selectedIndex = index);
                      },
                      childDelegate: ListWheelChildBuilderDelegate(
                        childCount: items.length,
                        builder: (context, index) {
                          if (index < 0 || index >= items.length) {
                            return null;
                          }
                          final item = items[index];
                          return _CaptureWheelSlot(
                            item: item,
                            centerFocus: _centerFocusFor(index),
                            colors: colors,
                            busy: _busy == item.choice,
                            disabled: _busy != null && _busy != item.choice,
                          );
                        },
                      ),
                    ),
                  ),
                  Positioned(
                    left: space.x2,
                    right: space.x2,
                    top: _flyoutHeight * 0.5 +
                        _CaptureCarouselMetrics.centerOrbDiameter * 0.55,
                    child: ExcludeSemantics(
                      child: _CaptureFocusedLabel(
                        label: items[labelIndex].label,
                        opacity: _centerLabelOpacity,
                        scale: _centerLabelScale,
                        maxWidth: _flyoutWidth - space.x2 * 2,
                        style: type.labelMedium.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 0,
                    height: 0,
                    child: Column(
                      children: [
                        for (final item in items)
                          Semantics(
                            button: true,
                            label: item.label,
                            enabled: _busy == null || _busy == item.choice,
                            onTap: _busy != null && _busy != item.choice
                                ? null
                                : () => unawaited(item.onTap()),
                            child: Tooltip(
                              message: item.label,
                              child: const SizedBox(width: 0, height: 0),
                            ),
                          ),
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

class _CaptureWheelSlot extends StatelessWidget {
  const _CaptureWheelSlot({
    required this.item,
    required this.centerFocus,
    required this.colors,
    required this.busy,
    required this.disabled,
  });

  final _CaptureChoiceItem item;
  final double centerFocus;
  final VamoSemanticColors colors;
  final bool busy;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    const iconSize = _CaptureCarouselMetrics.centerIconSize;
    final orbOpacity = disabled ? 0.42 : 1.0;

    return ExcludeSemantics(
      child: Tooltip(
        message: item.label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: disabled ? null : () => unawaited(item.onTap()),
          child: Center(
            child: centerFocus < 0.01
                ? const SizedBox(width: 1, height: 1)
                : Opacity(
                    opacity: orbOpacity,
                    child: _CaptureChoiceOrb(
                      diameter: _CaptureCarouselMetrics.centerOrbDiameter,
                      icon: item.icon,
                      iconSize: iconSize,
                      colors: colors,
                      selected: centerFocus > 0.85,
                      busy: busy,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _CaptureFocusedLabel extends StatelessWidget {
  const _CaptureFocusedLabel({
    required this.label,
    required this.opacity,
    required this.scale,
    required this.maxWidth,
    required this.style,
  });

  final String label;
  final double opacity;
  final double scale;
  final double maxWidth;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    if (opacity < 0.01) {
      return const SizedBox.shrink();
    }

    return Opacity(
      opacity: opacity,
      child: Transform.scale(
        scale: scale,
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: maxWidth,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.center,
            child: Text(
              label,
              style: style,
              textAlign: TextAlign.center,
              maxLines: 1,
              softWrap: false,
            ),
          ),
        ),
      ),
    );
  }
}

class _CaptureWheelNeighbors extends StatelessWidget {
  const _CaptureWheelNeighbors({
    required this.previous,
    required this.next,
    required this.colors,
    required this.busy,
  });

  final _CaptureChoiceItem? previous;
  final _CaptureChoiceItem? next;
  final VamoSemanticColors colors;
  final _CaptureChoice? busy;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        if (previous != null)
          Align(
            alignment: const Alignment(0, -0.72),
            child: _CaptureNeighborOrb(
              item: previous!,
              colors: colors,
              busy: busy == previous!.choice,
              dimmed: busy != null && busy != previous!.choice,
            ),
          ),
        if (next != null)
          Align(
            alignment: const Alignment(0, 0.72),
            child: _CaptureNeighborOrb(
              item: next!,
              colors: colors,
              busy: busy == next!.choice,
              dimmed: busy != null && busy != next!.choice,
            ),
          ),
      ],
    );
  }
}

class _CaptureNeighborOrb extends StatelessWidget {
  const _CaptureNeighborOrb({
    required this.item,
    required this.colors,
    required this.busy,
    required this.dimmed,
  });

  final _CaptureChoiceItem item;
  final VamoSemanticColors colors;
  final bool busy;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: dimmed
          ? _CaptureCarouselMetrics.busyDimOpacity
          : _CaptureCarouselMetrics.neighborOpacity,
      child: Transform.scale(
        scale: _CaptureCarouselMetrics.neighborScale,
        child: _CaptureChoiceOrb(
          diameter: _CaptureCarouselMetrics.neighborOrbDiameter,
          icon: item.icon,
          iconSize: _CaptureCarouselMetrics.neighborIconSize,
          colors: colors,
          selected: false,
          busy: busy,
        ),
      ),
    );
  }
}

enum _CaptureChoice { photo, video, note, background }

abstract final class _CaptureCarouselMetrics {
  static const flyoutWidth = 72.0;
  static const flyoutHeight = 276.0;
  static const wheelItemExtent = 78.0;

  /// Translucent pill over the hero (UI_REFERENCE §7).
  static const pillFillAlpha = 0.18;
  static const pillBorderAlpha = 0.26;

  /// Base orb size before [ListWheelScrollView] magnification (~1.6× at center).
  static const centerOrbDiameter = 28.0;
  static const centerIconSize = 18.0;

  static const neighborOrbDiameter = 32.0;
  static const neighborIconSize = 15.0;
  static const neighborScale = 0.44;
  static const neighborOpacity = 0.6;
  static const offCenterFillAlpha = 0.78;
  static const busyDimOpacity = 0.35;
}

class _CaptureChoiceItem {
  const _CaptureChoiceItem({
    required this.choice,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final _CaptureChoice choice;
  final IconData icon;
  final String label;
  final Future<void> Function() onTap;
}

class _CaptureChoiceOrb extends StatelessWidget {
  const _CaptureChoiceOrb({
    required this.diameter,
    required this.icon,
    required this.iconSize,
    required this.colors,
    required this.selected,
    required this.busy,
  });

  final double diameter;
  final IconData icon;
  final double iconSize;
  final VamoSemanticColors colors;
  final bool selected;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final fill = selected
        ? Colors.white
        : Colors.white.withValues(alpha: _CaptureCarouselMetrics.offCenterFillAlpha);

    return VamoCircleIcon(
      diameter: diameter,
      backgroundColor: fill,
      shadow: selected,
      child: busy
          ? SizedBox(
              width: iconSize,
              height: iconSize,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colors.secondary,
              ),
            )
          : Icon(icon, color: colors.secondary, size: iconSize),
    );
  }
}

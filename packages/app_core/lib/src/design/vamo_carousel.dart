import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'app_semantic_colors.dart';
import 'app_theme_context.dart';
import 'vamo_circle_icon.dart';

/// One selectable orb in a [VamoCarousel] / [showVamoCarousel] flyout.
class VamoCarouselItem {
  const VamoCarouselItem({
    required this.icon,
    required this.label,
    required this.onSelected,
    this.color,
    String? semanticLabel,
  }) : semanticLabel = semanticLabel ?? label;

  final IconData icon;
  final String label;
  final Future<void> Function() onSelected;
  final Color? color;
  final String semanticLabel;
}

const kVamoCarouselOverlayKey = ValueKey<String>('vamo-carousel-overlay');

/// Anchored vertical elliptical wheel flyout: magnified centered item, smaller
/// semi-solid neighbors, white-ring orbs ([VamoCircleIcon]), centered label,
/// dismiss on outside-tap.
Future<void> showVamoCarousel({
  required BuildContext context,
  LayerLink? anchor,
  required List<VamoCarouselItem> items,
  int? loadingIndex,
}) {
  if (items.isEmpty) {
    return Future.value();
  }
  return showVamoCarouselOverlay(
    context: context,
    anchorLink: anchor,
    flyoutBuilder: (dismiss) => VamoCarousel(
      items: items,
      loadingIndex: loadingIndex,
      onDismiss: dismiss,
    ),
  );
}

/// Overlay shell for a custom flyout (e.g. capture wiring with Riverpod).
Future<void> showVamoCarouselOverlay({
  required BuildContext context,
  LayerLink? anchorLink,
  required Widget Function(Future<void> Function() dismiss) flyoutBuilder,
}) {
  final overlay = Overlay.of(context, rootOverlay: true);
  final completer = Completer<void>();
  late final OverlayEntry entry;

  void removeEntry() {
    if (entry.mounted) entry.remove();
    if (!completer.isCompleted) completer.complete();
  }

  entry = OverlayEntry(
    builder: (_) => _VamoCarouselOverlay(
      anchorLink: anchorLink,
      onRemove: removeEntry,
      flyoutBuilder: flyoutBuilder,
    ),
  );

  overlay.insert(entry);
  return completer.future;
}

class VamoCarousel extends StatefulWidget {
  const VamoCarousel({
    super.key,
    required this.items,
    this.loadingIndex,
    this.onDismiss,
  });

  final List<VamoCarouselItem> items;
  final int? loadingIndex;
  final Future<void> Function()? onDismiss;

  @override
  State<VamoCarousel> createState() => _VamoCarouselState();
}

class _VamoCarouselState extends State<VamoCarousel> {
  static const _flyoutWidth = _VamoCarouselMetrics.flyoutWidth;
  static const _flyoutHeight = _VamoCarouselMetrics.flyoutHeight;
  static const _wheelItemExtent = _VamoCarouselMetrics.wheelItemExtent;

  FixedExtentScrollController? _wheelController;
  var _selectedIndex = 0;
  var _scrollIndex = 0.0;

  @override
  void initState() {
    super.initState();
    if (widget.items.isEmpty) return;
    assert(widget.items.isNotEmpty, 'VamoCarousel requires at least one item');
    _wheelController = FixedExtentScrollController();
    _wheelController!.addListener(_syncWheelScroll);
  }

  @override
  void dispose() {
    _wheelController?.removeListener(_syncWheelScroll);
    _wheelController?.dispose();
    super.dispose();
  }

  void _syncWheelScroll() {
    final controller = _wheelController;
    if (controller == null || !controller.hasClients || widget.items.isEmpty) {
      return;
    }
    final next = controller.offset / _wheelItemExtent;
    final index = next.round().clamp(0, widget.items.length - 1);
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

  bool _isDisabled(int index) {
    final loading = widget.loadingIndex;
    return loading != null && loading != index;
  }

  bool _isLoading(int index) => widget.loadingIndex == index;

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      return const SizedBox.shrink();
    }

    final colors = context.vamoColors;
    final type = context.vamoType;
    final space = context.vamoSpace;
    final items = widget.items;
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
                alpha: _VamoCarouselMetrics.pillFillAlpha,
              ),
              borderRadius: BorderRadius.circular(_flyoutWidth / 2),
              border: Border.all(
                color: Colors.white.withValues(
                  alpha: _VamoCarouselMetrics.pillBorderAlpha,
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
                      child: _VamoCarouselWheelNeighbors(
                        previousIndex:
                            _selectedIndex > 0 ? _selectedIndex - 1 : null,
                        nextIndex: _selectedIndex < items.length - 1
                            ? _selectedIndex + 1
                            : null,
                        previous: previousItem,
                        next: nextItem,
                        colors: colors,
                        loadingIndex: widget.loadingIndex,
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: ListWheelScrollView.useDelegate(
                      controller: _wheelController!,
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
                          return _VamoCarouselWheelSlot(
                            item: item,
                            centerFocus: _centerFocusFor(index),
                            colors: colors,
                            loading: _isLoading(index),
                            disabled: _isDisabled(index),
                          );
                        },
                      ),
                    ),
                  ),
                  Positioned(
                    left: space.x2,
                    right: space.x2,
                    top: _flyoutHeight * 0.5 +
                        _VamoCarouselMetrics.centerOrbDiameter * 0.55,
                    child: ExcludeSemantics(
                      child: _VamoCarouselFocusedLabel(
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
                        for (var i = 0; i < items.length; i++)
                          Semantics(
                            button: true,
                            label: items[i].semanticLabel,
                            enabled: !_isDisabled(i),
                            onTap: _isDisabled(i)
                                ? null
                                : () => unawaited(items[i].onSelected()),
                            child: Tooltip(
                              message: items[i].label,
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

class _VamoCarouselOverlay extends StatefulWidget {
  const _VamoCarouselOverlay({
    required this.anchorLink,
    required this.flyoutBuilder,
    required this.onRemove,
  });

  final LayerLink? anchorLink;
  final Widget Function(Future<void> Function() dismiss) flyoutBuilder;
  final VoidCallback onRemove;

  @override
  State<_VamoCarouselOverlay> createState() => _VamoCarouselOverlayState();
}

class _VamoCarouselOverlayState extends State<_VamoCarouselOverlay>
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
          child: widget.flyoutBuilder(_dismiss),
        ),
      ),
    );

    return Material(
      key: kVamoCarouselOverlayKey,
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

class _VamoCarouselWheelSlot extends StatelessWidget {
  const _VamoCarouselWheelSlot({
    required this.item,
    required this.centerFocus,
    required this.colors,
    required this.loading,
    required this.disabled,
  });

  final VamoCarouselItem item;
  final double centerFocus;
  final VamoSemanticColors colors;
  final bool loading;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    const iconSize = _VamoCarouselMetrics.centerIconSize;
    final orbOpacity = disabled ? 0.42 : 1.0;

    return ExcludeSemantics(
      child: Tooltip(
        message: item.label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: disabled ? null : () => unawaited(item.onSelected()),
          child: Center(
            child: centerFocus < 0.01
                ? const SizedBox(width: 1, height: 1)
                : Opacity(
                    opacity: orbOpacity,
                    child: _VamoCarouselOrb(
                      diameter: _VamoCarouselMetrics.centerOrbDiameter,
                      icon: item.icon,
                      iconSize: iconSize,
                      colors: colors,
                      accentColor: item.color,
                      selected: centerFocus > 0.85,
                      loading: loading,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _VamoCarouselFocusedLabel extends StatelessWidget {
  const _VamoCarouselFocusedLabel({
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

class _VamoCarouselWheelNeighbors extends StatelessWidget {
  const _VamoCarouselWheelNeighbors({
    required this.previousIndex,
    required this.nextIndex,
    required this.previous,
    required this.next,
    required this.colors,
    required this.loadingIndex,
  });

  final int? previousIndex;
  final int? nextIndex;
  final VamoCarouselItem? previous;
  final VamoCarouselItem? next;
  final VamoSemanticColors colors;
  final int? loadingIndex;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        if (previous != null && previousIndex != null)
          Align(
            alignment: const Alignment(0, -0.72),
            child: _VamoCarouselNeighborOrb(
              item: previous!,
              colors: colors,
              loading: loadingIndex == previousIndex,
              dimmed:
                  loadingIndex != null && loadingIndex != previousIndex,
            ),
          ),
        if (next != null && nextIndex != null)
          Align(
            alignment: const Alignment(0, 0.72),
            child: _VamoCarouselNeighborOrb(
              item: next!,
              colors: colors,
              loading: loadingIndex == nextIndex,
              dimmed: loadingIndex != null && loadingIndex != nextIndex,
            ),
          ),
      ],
    );
  }
}

class _VamoCarouselNeighborOrb extends StatelessWidget {
  const _VamoCarouselNeighborOrb({
    required this.item,
    required this.colors,
    required this.loading,
    required this.dimmed,
  });

  final VamoCarouselItem item;
  final VamoSemanticColors colors;
  final bool loading;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: dimmed
          ? _VamoCarouselMetrics.busyDimOpacity
          : _VamoCarouselMetrics.neighborOpacity,
      child: Transform.scale(
        scale: _VamoCarouselMetrics.neighborScale,
        child: _VamoCarouselOrb(
          diameter: _VamoCarouselMetrics.neighborOrbDiameter,
          icon: item.icon,
          iconSize: _VamoCarouselMetrics.neighborIconSize,
          colors: colors,
          accentColor: item.color,
          selected: false,
          loading: loading,
        ),
      ),
    );
  }
}

abstract final class _VamoCarouselMetrics {
  static const flyoutWidth = 72.0;
  static const flyoutHeight = 276.0;
  static const wheelItemExtent = 78.0;

  static const pillFillAlpha = 0.18;
  static const pillBorderAlpha = 0.26;

  static const centerOrbDiameter = 28.0;
  static const centerIconSize = 18.0;

  static const neighborOrbDiameter = 32.0;
  static const neighborIconSize = 15.0;
  static const neighborScale = 0.44;
  static const neighborOpacity = 0.6;
  static const offCenterFillAlpha = 0.78;
  static const busyDimOpacity = 0.35;
}

class _VamoCarouselOrb extends StatelessWidget {
  const _VamoCarouselOrb({
    required this.diameter,
    required this.icon,
    required this.iconSize,
    required this.colors,
    required this.selected,
    required this.loading,
    this.accentColor,
  });

  final double diameter;
  final IconData icon;
  final double iconSize;
  final VamoSemanticColors colors;
  final bool selected;
  final bool loading;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final fill = selected
        ? Colors.white
        : Colors.white.withValues(alpha: _VamoCarouselMetrics.offCenterFillAlpha);
    final iconColor = accentColor ?? colors.secondary;

    return VamoCircleIcon(
      diameter: diameter,
      backgroundColor: fill,
      shadow: selected,
      child: loading
          ? SizedBox(
              width: iconSize,
              height: iconSize,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: iconColor,
              ),
            )
          : Icon(icon, color: iconColor, size: iconSize),
    );
  }
}

import 'dart:ui' show lerpDouble;

import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../signals/coming_soon_sheet.dart';
import '../trips/trips_repository.dart';
import 'capture_repository.dart';

/// Compact capture choices (S30 / S44 carousel) — not the full [CaptureTab] feed.
Future<void> showCaptureActionSheet({
  required BuildContext context,
  required String tripId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (ctx) => CaptureChoiceSheet(tripId: tripId),
  );
}

class CaptureChoiceSheet extends ConsumerStatefulWidget {
  const CaptureChoiceSheet({super.key, required this.tripId});

  final String tripId;

  @override
  ConsumerState<CaptureChoiceSheet> createState() => _CaptureChoiceSheetState();
}

class _CaptureChoiceSheetState extends ConsumerState<CaptureChoiceSheet> {
  static const _viewportFraction = 0.3;
  static const _carouselHeight = 132.0;

  final _picker = ImagePicker();
  late final PageController _pageController;
  _CaptureChoice? _busy;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: _viewportFraction);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _addNote() async {
    Navigator.pop(context);
    await context.push(AppRoutes.tripAddCaptureNote(widget.tripId));
  }

  Future<void> _addPhoto() async {
    final picked = await _picker.pickImage(
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
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      showActionError(
        context,
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
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1920,
      maxHeight: 1920,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;

    setState(() => _busy = _CaptureChoice.background);
    try {
      await ref.read(tripsRepositoryProvider).setTripBackground(
            tripId: widget.tripId,
            sourcePath: picked.path,
          );
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      showActionError(
        context,
        ref,
        screen: 'trip_home',
        action: 'set_trip_background',
        error: e,
      );
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _addVideo() async {
    final picked = await _picker.pickVideo(source: ImageSource.gallery);
    if (picked == null || !mounted) return;
    if (!context.mounted) return;
    Navigator.pop(context);
    await showComingSoonSheet(
      context: context,
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
          icon: Icons.add_photo_alternate_outlined,
          label: 'Photo',
          onTap: _addPhoto,
        ),
        _CaptureChoiceItem(
          choice: _CaptureChoice.video,
          icon: Icons.videocam_outlined,
          label: 'Video',
          onTap: _addVideo,
        ),
        _CaptureChoiceItem(
          choice: _CaptureChoice.note,
          icon: Icons.note_add_outlined,
          label: 'Note',
          onTap: _addNote,
        ),
        _CaptureChoiceItem(
          choice: _CaptureChoice.background,
          icon: Icons.image_outlined,
          label: 'Background',
          onTap: _setBackground,
        ),
      ];

  double _focusFor(int index) {
    if (!_pageController.hasClients ||
        !_pageController.position.haveDimensions) {
      return index == _pageController.initialPage ? 1 : 0;
    }
    final page = _pageController.page ?? _pageController.initialPage.toDouble();
    return (1 - (page - index).abs()).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.vamoColors;
    final type = context.vamoType;
    final space = context.vamoSpace;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final items = _items();

    final disabled = _busy != null;

    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        0,
        space.x1,
        0,
        space.x3 + bottomInset,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(
            child: SizedBox(
              height: _carouselHeight,
              child: AnimatedBuilder(
                animation: _pageController,
                builder: (context, _) {
                  return PageView(
                  controller: _pageController,
                  clipBehavior: Clip.none,
                  padEnds: true,
                  children: [
                    for (var index = 0; index < items.length; index++)
                      _CaptureCarouselSlot(
                        item: items[index],
                        focus: _focusFor(index),
                        colors: colors,
                        type: type,
                        space: space,
                        motion: context.vamoMotion,
                        busy: _busy == items[index].choice,
                        disabled:
                            _busy != null && _busy != items[index].choice,
                      ),
                  ],
                  );
                },
              ),
            ),
          ),
          // Screen-reader / tap-through fallback — no swipe required.
          SizedBox(
            width: 0,
            height: 0,
            child: Column(
              children: [
                for (final item in items)
                  Semantics(
                    button: true,
                    label: item.label,
                    enabled: !disabled || _busy == item.choice,
                    onTap: disabled && _busy != item.choice
                        ? null
                        : item.onTap,
                    child: const SizedBox(width: 0, height: 0),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CaptureCarouselSlot extends StatelessWidget {
  const _CaptureCarouselSlot({
    required this.item,
    required this.focus,
    required this.colors,
    required this.type,
    required this.space,
    required this.motion,
    required this.busy,
    required this.disabled,
  });

  final _CaptureChoiceItem item;
  final double focus;
  final VamoSemanticColors colors;
  final VamoTypeScale type;
  final VamoSpacing space;
  final VamoMotion motion;
  final bool busy;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final scale = lerpDouble(0.72, 1.12, focus) ?? 1;
    final circleSize = lerpDouble(48, 72, focus) ?? 56;
    final iconSize = lerpDouble(22, 28, focus) ?? 24;
    final showLabel = focus > 0.72;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: disabled ? null : item.onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Transform.scale(
            scale: scale,
            child: _CaptureChoiceOrb(
              diameter: circleSize,
              icon: item.icon,
              iconSize: iconSize,
              colors: colors,
              busy: busy,
              dimmed: disabled,
            ),
          ),
          SizedBox(height: space.x2),
          SizedBox(
            height: 20,
            child: AnimatedOpacity(
              opacity: showLabel ? 1 : 0,
              duration: motion.instant,
              child: Text(
                item.label,
                style: type.labelSmall.copyWith(
                  color: colors.onSurface,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _CaptureChoice { photo, video, note, background }

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
  final VoidCallback onTap;
}

class _CaptureChoiceOrb extends StatelessWidget {
  const _CaptureChoiceOrb({
    required this.diameter,
    required this.icon,
    required this.iconSize,
    required this.colors,
    required this.busy,
    required this.dimmed,
  });

  final double diameter;
  final IconData icon;
  final double iconSize;
  final VamoSemanticColors colors;
  final bool busy;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: dimmed ? 0.45 : 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: colors.surface,
          border: Border.all(
            color: colors.divider.withValues(alpha: 0.7),
          ),
          boxShadow: [
            BoxShadow(
              color: colors.onSurface.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: SizedBox(
          width: diameter,
          height: diameter,
          child: Center(
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
          ),
        ),
      ),
    );
  }
}

import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../signals/coming_soon_sheet.dart';
import '../trips/trips_repository.dart';
import 'capture_repository.dart';

/// Compact capture choices (S30 / S44 carousel), shown as a hero-anchored flyout.
Future<void> showCaptureActionSheet({
  required BuildContext context,
  required String tripId,
  LayerLink? anchorLink,
}) {
  return showVamoCarouselOverlay(
    context: context,
    anchorLink: anchorLink,
    flyoutBuilder: (dismiss) => UncontrolledProviderScope(
      container: ProviderScope.containerOf(context),
      child: CaptureChoiceSheet(
        tripId: tripId,
        navigationContext: context,
        onDismiss: dismiss,
      ),
    ),
  );
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
  final _picker = ImagePicker();
  _CaptureChoice? _busy;

  int? get _loadingIndex => switch (_busy) {
        _CaptureChoice.photo => 0,
        _CaptureChoice.video => 1,
        _CaptureChoice.note => 2,
        _CaptureChoice.background => 3,
        null => null,
      };

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

  List<VamoCarouselItem> _items() => [
        VamoCarouselItem(
          icon: Icons.photo_camera_rounded,
          label: 'Photo',
          onSelected: _addPhoto,
        ),
        VamoCarouselItem(
          icon: Icons.videocam_rounded,
          label: 'Video',
          onSelected: _addVideo,
        ),
        VamoCarouselItem(
          icon: Icons.edit_note_rounded,
          label: 'Note',
          onSelected: _addNote,
        ),
        VamoCarouselItem(
          icon: Icons.wallpaper_rounded,
          label: 'Background',
          onSelected: _setBackground,
        ),
      ];

  @override
  Widget build(BuildContext context) {
    return VamoCarousel(
      items: _items(),
      loadingIndex: _loadingIndex,
      onDismiss: widget.onDismiss,
    );
  }
}

enum _CaptureChoice { photo, video, note, background }

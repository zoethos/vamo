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

/// Test override for [ImagePicker.pickVideo] — production uses [ImagePicker].
typedef CapturePickVideo = Future<XFile?> Function({
  required ImageSource source,
});

class CaptureChoiceSheet extends ConsumerStatefulWidget {
  const CaptureChoiceSheet({
    super.key,
    required this.tripId,
    this.navigationContext,
    this.onDismiss,
    @visibleForTesting this.pickImage,
    @visibleForTesting this.pickVideo,
  });

  final String tripId;
  final BuildContext? navigationContext;
  final Future<void> Function()? onDismiss;

  @visibleForTesting
  final CapturePickImage? pickImage;

  @visibleForTesting
  final CapturePickVideo? pickVideo;

  @override
  ConsumerState<CaptureChoiceSheet> createState() => _CaptureChoiceSheetState();
}

class _CaptureChoiceSheetState extends ConsumerState<CaptureChoiceSheet> {
  final _picker = ImagePicker();

  BuildContext get _routeContext => widget.navigationContext ?? context;

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

  Future<void> _runCaptureAction({
    required String action,
    required Future<XFile?> Function() pick,
    required Future<void> Function(String path, ProviderContainer container) run,
  }) async {
    final routeContext = _routeContext;
    try {
      final picked = await pick();
      if (picked == null || !mounted) return;
      final container = ProviderScope.containerOf(routeContext, listen: false);
      await _dismiss();
      if (!routeContext.mounted) return;
      await run(picked.path, container);
    } catch (e, st) {
      debugPrint('CAPTURE-FAIL [$action]: $e\n$st');
      if (!routeContext.mounted) return;
      if (mounted) {
        await _dismiss();
      }
      showActionError(
        routeContext,
        ref,
        screen: 'trip_home',
        action: action,
        error: e,
        stackTrace: st,
      );
    }
  }

  Future<void> _runDismissAction({
    required String action,
    required Future<void> Function() run,
  }) async {
    final routeContext = _routeContext;
    try {
      await _dismiss();
      if (!routeContext.mounted) return;
      await run();
    } catch (e, st) {
      debugPrint('CAPTURE-FAIL [$action]: $e\n$st');
      if (!routeContext.mounted) return;
      showActionError(
        routeContext,
        ref,
        screen: 'trip_home',
        action: action,
        error: e,
        stackTrace: st,
      );
    }
  }

  Future<void> _addNote() {
    final routeContext = _routeContext;
    return _runDismissAction(
      action: 'add_capture_note',
      run: () => routeContext.push(AppRoutes.tripAddCaptureNote(widget.tripId)),
    );
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

  Future<XFile?> _pickVideo({required ImageSource source}) {
    final override = widget.pickVideo;
    if (override != null) {
      return override(source: source);
    }
    return _picker.pickVideo(source: source);
  }

  Future<void> _addPhoto() {
    return _runCaptureAction(
      action: 'add_capture_photo',
      pick: () => _pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 80,
      ),
      run: (path, container) => container.read(captureRepositoryProvider).addPhoto(
            tripId: widget.tripId,
            sourcePath: path,
          ),
    );
  }

  Future<void> _setBackground() {
    return _runCaptureAction(
      action: 'set_trip_background',
      pick: () => _pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      ),
      run: (path, container) =>
          container.read(tripsRepositoryProvider).setTripBackground(
                tripId: widget.tripId,
                sourcePath: path,
              ),
    );
  }

  Future<void> _addVideo() {
    final routeContext = _routeContext;
    return _runCaptureAction(
      action: 'add_capture_video',
      pick: () => _pickVideo(source: ImageSource.gallery),
      run: (_, __) => showComingSoonSheet(
        context: routeContext,
        ref: ref,
        interestEvent: VamoEvent.recapInterestTapped,
        feature: 'capture_video',
        title: 'Trip videos',
        description:
            'Short video memories from your trip will land here in a later wave.',
      ),
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
      onDismiss: widget.onDismiss,
    );
  }
}

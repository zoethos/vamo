import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../signals/coming_soon_sheet.dart';
import '../trips/trips_repository.dart';
import 'capture_repository.dart';

const _captureScreen = 'trip_home';

/// Compact capture choices (S30 / S44 carousel), shown as a hero-anchored flyout.
Future<void> showCaptureActionSheet({
  required BuildContext context,
  required String tripId,
  LayerLink? anchorLink,
}) {
  final container = ProviderScope.containerOf(context, listen: false);
  return showVamoCarouselOverlay(
    context: context,
    anchorLink: anchorLink,
    flyoutBuilder: (dismiss) => UncontrolledProviderScope(
      container: container,
      child: CaptureChoiceSheet(
        tripId: tripId,
        navigationContext: context,
        providerContainer: container,
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
    this.providerContainer,
    this.onDismiss,
    @visibleForTesting this.pickImage,
    @visibleForTesting this.pickVideo,
  });

  final String tripId;
  final BuildContext? navigationContext;

  /// Trip-home scope, captured before the overlay opens — never the flyout scope.
  final ProviderContainer? providerContainer;
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

  ProviderContainer get _rootContainer {
    final passed = widget.providerContainer;
    if (passed != null) return passed;
    return ProviderScope.containerOf(_routeContext, listen: false);
  }

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

  void _reportActionError({
    required String action,
    required Object error,
    required StackTrace stackTrace,
    required ProviderContainer container,
  }) {
    final routeContext = _routeContext;
    if (routeContext.mounted) {
      showActionError(
        routeContext,
        ref,
        screen: 'trip_home',
        action: action,
        error: error,
        stackTrace: stackTrace,
      );
      return;
    }
    reportAndLog(
      error,
      stackTrace,
      screen: 'trip_home',
      action: action,
      analytics: container.read(analyticsProvider),
    );
  }

  void _dismissOverlayFireAndForget({
    required Analytics analytics,
    required String action,
  }) {
    unawaited(
      _dismiss().catchError((Object e, StackTrace st) {
        analytics.reportCaptureActionAbandoned(
          screen: _captureScreen,
          action: action,
          reason: 'dismiss_failed',
        );
      }),
    );
  }

  Future<void> _runCaptureAction({
    required String action,
    required Future<XFile?> Function() pick,
    required Future<void> Function(String path, ProviderContainer container) run,
  }) async {
    final container = _rootContainer;
    final analytics = container.read(analyticsProvider);
    try {
      final picked = await pick();
      if (picked == null) {
        analytics.reportCaptureActionAbandoned(
          screen: _captureScreen,
          action: action,
          reason: 'cancelled',
        );
        return;
      }
      final sheetMounted = mounted;
      analytics.reportCaptureActionStarted(
        screen: _captureScreen,
        action: action,
        sheetMounted: sheetMounted,
      );
      if (!sheetMounted) {
        analytics.reportCaptureActionAbandoned(
          screen: _captureScreen,
          action: action,
          reason: 'unmounted_after_pick',
        );
      }
      _dismissOverlayFireAndForget(analytics: analytics, action: action);
      await run(picked.path, container);
      analytics.reportCaptureActionCompleted(
        screen: _captureScreen,
        action: action,
      );
    } catch (e, st) {
      debugPrint('CAPTURE-FAIL [$action]: $e\n$st');
      _dismissOverlayFireAndForget(analytics: analytics, action: action);
      _reportActionError(
        action: action,
        error: e,
        stackTrace: st,
        container: container,
      );
    }
  }

  Future<void> _runDismissAction({
    required String action,
    required Future<void> Function() run,
  }) async {
    final container = _rootContainer;
    final analytics = container.read(analyticsProvider);
    try {
      _dismissOverlayFireAndForget(analytics: analytics, action: action);
      analytics.reportCaptureActionStarted(
        screen: _captureScreen,
        action: action,
        sheetMounted: mounted,
      );
      await run();
      analytics.reportCaptureActionCompleted(
        screen: _captureScreen,
        action: action,
      );
    } catch (e, st) {
      debugPrint('CAPTURE-FAIL [$action]: $e\n$st');
      _reportActionError(
        action: action,
        error: e,
        stackTrace: st,
        container: container,
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
      run: (_, container) => showComingSoonSheet(
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

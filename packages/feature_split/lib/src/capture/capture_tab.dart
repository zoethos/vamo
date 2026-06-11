import 'dart:io';

import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:video_player/video_player.dart';

import 'capture_models.dart';
import 'capture_providers.dart';
import 'capture_repository.dart';

/// Slice 8 — solo trip memories (notes + photos) feeding the snapshot card.
class CaptureTab extends ConsumerStatefulWidget {
  const CaptureTab({
    super.key,
    required this.tripId,
    this.showInlineAddActions = true,
  });

  final String tripId;
  final bool showInlineAddActions;

  @override
  ConsumerState<CaptureTab> createState() => _CaptureTabState();
}

class _CaptureTabState extends ConsumerState<CaptureTab> {
  final _picker = ImagePicker();
  bool _uploadingPhoto = false;

  Future<void> _pickPhoto() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 80,
    );
    if (picked == null) return;

    setState(() => _uploadingPhoto = true);
    try {
      await ref.read(captureRepositoryProvider).addPhoto(
            tripId: widget.tripId,
            sourcePath: picked.path,
          );
    } catch (e, stackTrace) {
      if (!mounted) return;
      showActionError(
        context,
        ref,
        screen: 'trip_home',
        action: 'add_capture_photo',
        error: e,
        stackTrace: stackTrace,
      );
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.vamoColors;
    final type = context.vamoType;
    final space = context.vamoSpace;

    final notes = ref.watch(tripNotesProvider(widget.tripId));
    final photos = ref.watch(tripPhotosProvider(widget.tripId));
    final videos = ref.watch(tripVideosProvider(widget.tripId));

    return notes.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => AppErrorState(
        screen: 'trip_home',
        message: formatActionFailureMessage(e),
        kind: classifyActionFailureKind(e),
        onRetry: () => ref.invalidate(tripNotesProvider(widget.tripId)),
      ),
      data: (noteList) => photos.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AppErrorState(
          screen: 'trip_home',
          message: formatActionFailureMessage(e),
          kind: classifyActionFailureKind(e),
          onRetry: () => ref.invalidate(tripPhotosProvider(widget.tripId)),
        ),
        data: (photoList) => videos.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => AppErrorState(
            screen: 'trip_home',
            message: formatActionFailureMessage(e),
            kind: classifyActionFailureKind(e),
            onRetry: () => ref.invalidate(tripVideosProvider(widget.tripId)),
          ),
          data: (videoList) {
            final empty =
                noteList.isEmpty && photoList.isEmpty && videoList.isEmpty;

            return ListView(
              padding: EdgeInsets.all(space.x4),
              children: [
                if (widget.showInlineAddActions) ...[
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => context.push(
                            AppRoutes.tripAddCaptureNote(widget.tripId),
                          ),
                          icon: const Icon(Icons.note_add_outlined),
                          label: const Text('Add note'),
                        ),
                      ),
                      SizedBox(width: space.x3),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _uploadingPhoto ? null : _pickPhoto,
                          icon: _uploadingPhoto
                              ? SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: colors.onPrimary,
                                  ),
                                )
                              : const Icon(Icons.add_photo_alternate_outlined),
                          label: const Text('Add photo'),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: space.x2),
                  Text(
                    'Memories appear on your shared snapshot card.',
                    style:
                        type.bodySmall.copyWith(color: colors.onSurfaceMuted),
                  ),
                ],
                if (empty) ...[
                  SizedBox(height: space.x12),
                  Icon(
                    Icons.auto_stories_outlined,
                    size: 56,
                    color: colors.emptyStateIcon,
                  ),
                  SizedBox(height: space.x4),
                  Text(
                    'Capture your trip',
                    textAlign: TextAlign.center,
                    style: type.titleLarge.copyWith(color: colors.onSurface),
                  ),
                  SizedBox(height: space.x2),
                  Text(
                    'Add notes, photos, and videos — they show up when you share your snapshot.',
                    textAlign: TextAlign.center,
                    style:
                        type.bodyMedium.copyWith(color: colors.onSurfaceMuted),
                  ),
                ],
                if (photoList.isNotEmpty) ...[
                  SizedBox(height: space.x6),
                  Text(
                    'Photos',
                    style: type.titleMedium.copyWith(
                      color: colors.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: space.x3),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    itemCount: photoList.length,
                    itemBuilder: (context, i) {
                      final photo = photoList[i];
                      return CapturePhotoCell(
                        key: ValueKey(photo.id),
                        tripId: widget.tripId,
                        photo: photo,
                      );
                    },
                  ),
                ],
                if (videoList.isNotEmpty) ...[
                  SizedBox(height: space.x6),
                  Text(
                    'Videos',
                    style: type.titleMedium.copyWith(
                      color: colors.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: space.x3),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                      childAspectRatio: 1.3,
                    ),
                    itemCount: videoList.length,
                    itemBuilder: (context, i) {
                      final video = videoList[i];
                      return CaptureVideoCell(
                        key: ValueKey(video.id),
                        tripId: widget.tripId,
                        video: video,
                      );
                    },
                  ),
                ],
                if (noteList.isNotEmpty) ...[
                  SizedBox(height: space.x6),
                  Text(
                    'Notes',
                    style: type.titleMedium.copyWith(
                      color: colors.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: space.x2),
                  ...noteList.map((n) {
                    final when =
                        DateFormat.MMMd().format(n.capturedAt.toLocal());
                    return Card(
                      margin: EdgeInsets.only(bottom: space.x2 + 2),
                      child: ListTile(
                        title: Text(n.title),
                        subtitle: Text(
                          n.body.isEmpty ? when : '${n.body}\n$when',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    );
                  }),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class CapturePhotoCell extends ConsumerStatefulWidget {
  const CapturePhotoCell({
    super.key,
    required this.tripId,
    required this.photo,
  });

  final String tripId;
  final TripPhotoView photo;

  @override
  ConsumerState<CapturePhotoCell> createState() => _CapturePhotoCellState();
}

class _CapturePhotoCellState extends ConsumerState<CapturePhotoCell> {
  late TripPhotoView _photo;
  Object? _lastReportedError;

  @override
  void initState() {
    super.initState();
    _photo = widget.photo;
    _reportLoadFailure(_photo.loadError);
  }

  @override
  void didUpdateWidget(covariant CapturePhotoCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.photo.id != widget.photo.id ||
        oldWidget.photo.loadError != widget.photo.loadError) {
      _photo = widget.photo;
      _reportLoadFailure(_photo.loadError);
    }
  }

  void _reportLoadFailure(Object? error) {
    if (error == null ||
        !widget.photo.hasRemoteStoragePath ||
        identical(error, _lastReportedError)) {
      return;
    }
    _lastReportedError = error;
    reportAndLog(
      error,
      StackTrace.current,
      screen: 'trip_home',
      action: 'load_photo',
      analytics: ref.read(analyticsProvider),
    );
  }

  Future<void> _retry() async {
    final loaded =
        await ref.read(captureRepositoryProvider).retryPhotoLoad(_photo.id);
    if (!mounted) return;
    setState(() => _photo = loaded);
    _reportLoadFailure(loaded.loadError);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.vamoColors;
    final path = _photo.displayPath;
    if (path != null && path.isNotEmpty && File(path).existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.file(File(path), fit: BoxFit.cover),
      );
    }

    if (_photo.loadError != null && _photo.hasRemoteStoragePath) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: StorageUnavailablePlaceholder(
          compact: true,
          label: 'Photo unavailable',
          onRetry: _retry,
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: ColoredBox(
        color: colors.surfaceMuted,
        child: Center(
          child: Icon(Icons.photo_outlined, color: colors.onSurfaceMuted),
        ),
      ),
    );
  }
}

class CaptureVideoCell extends ConsumerStatefulWidget {
  const CaptureVideoCell({
    super.key,
    required this.tripId,
    required this.video,
  });

  final String tripId;
  final TripVideoView video;

  @override
  ConsumerState<CaptureVideoCell> createState() => _CaptureVideoCellState();
}

class _CaptureVideoCellState extends ConsumerState<CaptureVideoCell> {
  late TripVideoView _video;
  Object? _lastReportedError;

  @override
  void initState() {
    super.initState();
    _video = widget.video;
    _reportLoadFailure(_video.loadError);
  }

  @override
  void didUpdateWidget(covariant CaptureVideoCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.video.id != widget.video.id ||
        oldWidget.video.loadError != widget.video.loadError) {
      _video = widget.video;
      _reportLoadFailure(_video.loadError);
    }
  }

  void _reportLoadFailure(Object? error) {
    if (error == null ||
        !widget.video.hasRemoteStoragePath ||
        identical(error, _lastReportedError)) {
      return;
    }
    _lastReportedError = error;
    reportAndLog(
      error,
      StackTrace.current,
      screen: 'trip_home',
      action: 'load_video',
      analytics: ref.read(analyticsProvider),
    );
  }

  Future<void> _retry() async {
    final loaded =
        await ref.read(captureRepositoryProvider).retryVideoLoad(_video.id);
    if (!mounted) return;
    setState(() => _video = loaded);
    _reportLoadFailure(loaded.loadError);
  }

  Future<void> _openVideo() async {
    final path = _video.displayPath;
    if (path == null || path.isEmpty) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => CaptureVideoPlayerScreen(
          path: path,
          title: _video.caption,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.vamoColors;
    final type = context.vamoType;
    final path = _video.displayPath;
    final exists = path != null && path.isNotEmpty && File(path).existsSync();
    if (exists) {
      final label = (_video.caption?.trim().isNotEmpty ?? false)
          ? _video.caption!.trim()
          : DateFormat.MMMd().format(_video.capturedAt.toLocal());
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Material(
          color: colors.surfaceMuted,
          child: InkWell(
            onTap: _openVideo,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Center(
                  child: Icon(
                    Icons.play_circle_fill_rounded,
                    color: colors.primary,
                    size: 44,
                  ),
                ),
                Positioned(
                  left: 8,
                  right: 8,
                  bottom: 8,
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: type.labelMedium.copyWith(
                      color: colors.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_video.loadError != null && _video.hasRemoteStoragePath) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: StorageUnavailablePlaceholder(
          compact: true,
          label: 'Video unavailable',
          onRetry: _retry,
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: ColoredBox(
        color: colors.surfaceMuted,
        child: Center(
          child: Icon(Icons.videocam_outlined, color: colors.onSurfaceMuted),
        ),
      ),
    );
  }
}

class CaptureVideoPlayerScreen extends ConsumerStatefulWidget {
  const CaptureVideoPlayerScreen({
    super.key,
    required this.path,
    this.title,
  });

  final String path;
  final String? title;

  @override
  ConsumerState<CaptureVideoPlayerScreen> createState() =>
      _CaptureVideoPlayerScreenState();
}

class _CaptureVideoPlayerScreenState
    extends ConsumerState<CaptureVideoPlayerScreen> {
  late final VideoPlayerController _controller;
  late final Future<void> _initialize;
  Object? _loadError;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.path));
    _controller.addListener(_onVideoChanged);
    _initialize = _controller.initialize().then((_) async {
      await _controller.play();
      if (mounted) setState(() {});
    }).catchError((Object error, StackTrace stackTrace) {
      reportAndLog(
        error,
        stackTrace,
        screen: 'trip_home',
        action: 'play_video',
        analytics: ref.read(analyticsProvider),
      );
      if (mounted) setState(() => _loadError = error);
      Error.throwWithStackTrace(error, stackTrace);
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_onVideoChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onVideoChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _togglePlay() async {
    if (!_controller.value.isInitialized) return;
    if (_controller.value.isPlaying) {
      await _controller.pause();
    } else {
      await _controller.play();
    }
  }

  Future<void> _seekTo(double milliseconds) {
    return _controller.seekTo(
      Duration(milliseconds: milliseconds.round()),
    );
  }

  String _formatDuration(Duration value) {
    final minutes = value.inMinutes.remainder(60).toString();
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    final hours = value.inHours;
    if (hours == 0) return '$minutes:$seconds';
    return '$hours:${minutes.padLeft(2, '0')}:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.title?.trim();
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          title == null || title.isEmpty ? 'Video' : title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SafeArea(
        child: FutureBuilder<void>(
          future: _initialize,
          builder: (context, snapshot) {
            if (_loadError != null || snapshot.hasError) {
              final error = _loadError ?? snapshot.error!;
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    formatActionFailureMessage(error),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              );
            }
            if (snapshot.connectionState != ConnectionState.done ||
                !_controller.value.isInitialized) {
              return const Center(child: CircularProgressIndicator());
            }

            final value = _controller.value;
            final durationMs = value.duration.inMilliseconds;
            final positionMs = value.position.inMilliseconds.clamp(
              0,
              durationMs == 0 ? 1 : durationMs,
            );

            return Column(
              children: [
                Expanded(
                  child: Center(
                    child: AspectRatio(
                      aspectRatio:
                          value.aspectRatio == 0 ? 16 / 9 : value.aspectRatio,
                      child: VideoPlayer(_controller),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: _togglePlay,
                        color: Colors.white,
                        icon: Icon(
                          value.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                        ),
                      ),
                      Text(
                        _formatDuration(value.position),
                        style: const TextStyle(color: Colors.white),
                      ),
                      Expanded(
                        child: Slider(
                          value: positionMs.toDouble(),
                          max: (durationMs == 0 ? 1 : durationMs).toDouble(),
                          onChanged: _seekTo,
                        ),
                      ),
                      Text(
                        _formatDuration(value.duration),
                        style: const TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

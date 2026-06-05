import 'dart:io';

import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import 'capture_models.dart';
import 'capture_providers.dart';
import 'capture_repository.dart';

/// Slice 8 — solo trip memories (notes + photos) feeding the snapshot card.
class CaptureTab extends ConsumerStatefulWidget {
  const CaptureTab({super.key, required this.tripId});

  final String tripId;

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
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final notes = ref.watch(tripNotesProvider(widget.tripId));
    final photos = ref.watch(tripPhotosProvider(widget.tripId));

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
        data: (photoList) {
          final empty = noteList.isEmpty && photoList.isEmpty;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
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
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _uploadingPhoto ? null : _pickPhoto,
                      icon: _uploadingPhoto
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.add_photo_alternate_outlined),
                      label: const Text('Add photo'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Memories appear on your shared snapshot card.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.graphite),
              ),
              if (empty) ...[
                const SizedBox(height: 48),
                const Icon(Icons.auto_stories_outlined,
                    size: 56, color: AppColors.jadeTeal),
                const SizedBox(height: 16),
                Text(
                  'Capture your trip',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: AppColors.ink,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Add notes and photos — they show up when you share your snapshot.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: AppColors.graphite),
                ),
              ],
              if (photoList.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text(
                  'Photos',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppColors.ink,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 12),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
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
              if (noteList.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text(
                  'Notes',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppColors.ink,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 8),
                ...noteList.map((n) {
                  final when =
                      DateFormat.MMMd().format(n.capturedAt.toLocal());
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
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
    ref.read(analyticsProvider).reportActionFailed(
          screen: 'trip_home',
          action: 'load_photo',
          error: error,
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
        color: AppColors.blush,
        child: Center(
          child: Icon(Icons.photo_outlined, color: AppColors.graphite),
        ),
      ),
    );
  }
}

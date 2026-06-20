import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Member avatar backed by the cached private-bucket signed URL provider.
class CachedMemberAvatar extends ConsumerWidget {
  const CachedMemberAvatar({
    super.key,
    required this.displayName,
    this.avatarStoragePath,
    this.avatarDisplayMode = AvatarDisplayMode.photo,
    this.avatarInitials,
    this.radius = 22,
  });

  final String displayName;
  final String? avatarStoragePath;
  final AvatarDisplayMode avatarDisplayMode;
  final String? avatarInitials;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final useInitials = avatarDisplayMode == AvatarDisplayMode.initials;
    if (useInitials ||
        avatarStoragePath == null ||
        avatarStoragePath!.isEmpty) {
      return VamoAvatar(
        displayName: displayName,
        initials: avatarInitials,
        radius: radius,
      );
    }
    final photoUrl =
        ref.watch(memberAvatarPhotoUrlProvider(avatarStoragePath)).valueOrNull;
    return VamoAvatar(
      displayName: displayName,
      initials: avatarInitials,
      photoUrl: photoUrl,
      radius: radius,
    );
  }
}

import 'package:flutter/material.dart';

import '../profile/profile_identity.dart';
import 'app_colors.dart';
import 'app_semantic_colors.dart';
import 'app_theme_context.dart';
import 'app_type_scale.dart';
import 'brand_assets.dart';

/// Shared avatar — stored photo, initials, brand mark, or person silhouette.
class VamoAvatar extends StatelessWidget {
  const VamoAvatar({
    super.key,
    this.displayName,
    this.photoUrl,
    this.radius = 22,
    this.showNameLabel = false,
    this.useBrandMark = false,
    this.overflowCount,
  });

  final String? displayName;
  final String? photoUrl;
  final double radius;
  final bool showNameLabel;

  /// Brand/mock slot — Vamo mark instead of a person silhouette.
  final bool useBrandMark;

  /// When set, renders a "+N" overflow badge (not a letter initial).
  final int? overflowCount;

  @override
  Widget build(BuildContext context) {
    final colors = context.vamoColors;
    final type = context.vamoType;
    final diameter = radius * 2;

    Widget avatar;
    if (overflowCount != null) {
      avatar = CircleAvatar(
        radius: radius,
        backgroundColor: colors.surfaceMuted,
        child: Text(
          '+$overflowCount',
          style: type.labelMedium.copyWith(
            color: colors.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    } else if (photoUrl != null && photoUrl!.isNotEmpty) {
      avatar = _PhotoAvatar(
        photoUrl: photoUrl!,
        radius: radius,
        fallback: _buildInitialsOrSilhouette(
          displayName: displayName,
          radius: radius,
          colors: colors,
          type: type,
          useBrandMark: useBrandMark,
        ),
      );
    } else {
      avatar = _buildInitialsOrSilhouette(
        displayName: displayName,
        radius: radius,
        colors: colors,
        type: type,
        useBrandMark: useBrandMark,
      );
    }

    if (!showNameLabel || displayName == null || displayName!.isEmpty) {
      return Semantics(label: displayName, child: avatar);
    }

    return Semantics(
      label: displayName,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          avatar,
          SizedBox(height: context.vamoSpace.x1),
          SizedBox(
            width: diameter + 12,
            child: Text(
              displayName!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: type.labelSmall.copyWith(color: colors.onSurfaceMuted),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _buildInitialsOrSilhouette({
    required String? displayName,
    required double radius,
    required VamoSemanticColors colors,
    required VamoTypeScale type,
    required bool useBrandMark,
  }) {
    final initials = avatarInitialsFromDisplayName(displayName);
    if (initials != null) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: AppColors.jadeTeal,
        child: Text(
          initials,
          style: type.labelMedium.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }
    if (useBrandMark) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: colors.surfaceMuted,
        child: Padding(
          padding: EdgeInsets.all(radius * 0.35),
          child: Image.asset(
            BrandAssets.primaryMark,
            fit: BoxFit.contain,
          ),
        ),
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: colors.surfaceMuted,
      child: Icon(
        Icons.person_outline,
        color: colors.onSurfaceMuted,
        size: radius * 0.95,
      ),
    );
  }
}

class _PhotoAvatar extends StatelessWidget {
  const _PhotoAvatar({
    required this.photoUrl,
    required this.radius,
    required this.fallback,
  });

  final String photoUrl;
  final double radius;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    final diameter = radius * 2;
    return ClipOval(
      child: Image.network(
        photoUrl,
        width: diameter,
        height: diameter,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
  }
}

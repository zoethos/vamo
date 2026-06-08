import 'package:flutter/material.dart';

import 'app_theme_context.dart';
import 'brand_assets.dart';

/// Shared avatar — person silhouette when no photo; brand mark for placeholders.
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
      avatar = CircleAvatar(
        radius: radius,
        backgroundColor: colors.surfaceMuted,
        backgroundImage: NetworkImage(photoUrl!),
      );
    } else if (useBrandMark) {
      avatar = CircleAvatar(
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
    } else {
      avatar = CircleAvatar(
        radius: radius,
        backgroundColor: colors.surfaceMuted,
        child: Icon(
          Icons.person_outline,
          color: colors.onSurfaceMuted,
          size: radius * 0.95,
        ),
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
}

import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';

import '../expenses/expense_models.dart';
import 'cached_member_avatar.dart';

/// Circular member avatars with trailing add tile (S35 dashboard).
class MemberAvatarRow extends StatelessWidget {
  const MemberAvatarRow({
    super.key,
    required this.members,
    required this.onAdd,
    this.maxVisible = 5,
  });

  final List<TripMemberView> members;
  final VoidCallback onAdd;
  final int maxVisible;

  static const _tileDiameter = 40.0;
  static const _avatarRadius = 18.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.vamoColors;
    final space = context.vamoSpace;
    final visible = members.take(maxVisible).toList(growable: false);
    final overflow = members.length - visible.length;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final member in visible) ...[
            VamoCircleIcon(
              diameter: _tileDiameter,
              child: CachedMemberAvatar(
                displayName: member.displayName,
                avatarStoragePath: member.avatarUrl,
                radius: _avatarRadius,
              ),
            ),
            SizedBox(width: space.x2),
          ],
          if (overflow > 0) ...[
            VamoCircleIcon(
              diameter: _tileDiameter,
              child: VamoAvatar(overflowCount: overflow, radius: _avatarRadius),
            ),
            SizedBox(width: space.x2),
          ],
          VamoCircleIcon(
            diameter: _tileDiameter,
            backgroundColor: colors.surfaceMuted,
            onTap: onAdd,
            child: Icon(Icons.add, color: colors.secondary, size: 20),
          ),
        ],
      ),
    );
  }
}

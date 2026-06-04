import 'dart:io';

import 'package:flutter/material.dart';

import '../expenses/money_format.dart';
import 'snapshot_models.dart';
import 'snapshot_themes.dart';

/// Fixed-size branded card rasterized for the share sheet (1080×1350 @ 3×).
class SnapshotBrandedCard extends StatelessWidget {
  const SnapshotBrandedCard({
    super.key,
    required this.data,
    this.theme = SnapshotThemes.defaultPack,
    this.width = 360,
    this.height = 450,
  });

  final SnapshotCardData data;
  final SnapshotThemePack theme;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final total = formatMoneyFromCents(
      data.totalSpentCents,
      data.baseCurrency,
    );
    final visibleMembers = data.members.take(6).toList();
    final overflow = data.members.length - visibleMembers.length;

    return SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: theme.gradient,
          ),
          borderRadius: const BorderRadius.all(Radius.circular(24)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                data.tripName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  height: 1.15,
                  letterSpacing: -0.5,
                ),
              ),
              if (data.destination != null && data.destination!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  data.destination!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 15,
                  ),
                ),
              ],
              if (data.dateRange != null) ...[
                const SizedBox(height: 4),
                Text(
                  data.dateRange!,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 13,
                  ),
                ),
              ],
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: theme.statBackground.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total spent',
                      style: TextStyle(
                        color: theme.statMuted,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      total,
                      style: TextStyle(
                        color: theme.statPrimary,
                        fontSize: 36,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1,
                      ),
                    ),
                    if (data.expenseCount > 0)
                      Text(
                        '${data.expenseCount} expense${data.expenseCount == 1 ? '' : 's'}',
                        style: TextStyle(
                          color: theme.statMuted,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              if (data.capture.photoPaths.isNotEmpty) ...[
                const SizedBox(height: 14),
                SizedBox(
                  height: 52,
                  child: Row(
                    children: [
                      for (var i = 0; i < data.capture.photoPaths.length; i++)
                        Padding(
                          padding: EdgeInsets.only(right: i < 2 ? 6 : 0),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(
                              File(data.capture.photoPaths[i]),
                              width: 52,
                              height: 52,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              if (data.capture.noteTitle != null &&
                  data.capture.noteTitle!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  data.capture.noteTitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.95),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (data.capture.noteExcerpt != null &&
                    data.capture.noteExcerpt!.isNotEmpty)
                  Text(
                    data.capture.noteExcerpt!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontSize: 12,
                    ),
                  ),
              ],
              const SizedBox(height: 20),
              if (visibleMembers.isNotEmpty)
                Row(
                  children: [
                    for (final m in visibleMembers)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: _MemberBubble(
                          initial: m.initial,
                          fill: theme.memberBubble,
                          textColor: theme.memberInitial,
                        ),
                      ),
                    if (overflow > 0)
                      Text(
                        '+$overflow',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              const Spacer(),
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: theme.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'Vamo',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      theme.tagline,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.75),
                        fontSize: 14,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MemberBubble extends StatelessWidget {
  const _MemberBubble({
    required this.initial,
    required this.fill,
    required this.textColor,
  });

  final String initial;
  final Color fill;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: Text(
        initial,
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.w700,
          fontSize: 16,
        ),
      ),
    );
  }
}

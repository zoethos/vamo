import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';

/// Recent expense row with category icon, amount, and relative time (S35).
class DashboardActivityRow extends StatelessWidget {
  const DashboardActivityRow({
    super.key,
    required this.description,
    required this.category,
    required this.amount,
    required this.occurredAt,
    this.now,
  });

  final String description;
  final String? category;
  final String amount;
  final DateTime occurredAt;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final colors = context.vamoColors;
    final type = context.vamoType;
    final space = context.vamoSpace;
    final shape = context.vamoShape;
    final entry = CategoryCatalog.resolve(category);
    final relative = formatRelativeTime(occurredAt, now: now);

    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(space.x4, 0, space.x4, space.x2),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: shape.controlBorderRadius,
          border: Border.all(color: colors.divider.withValues(alpha: 0.5)),
        ),
        child: Padding(
          padding: EdgeInsetsDirectional.all(space.x3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: entry.color.withValues(alpha: 0.16),
                  borderRadius: shape.controlBorderRadius,
                ),
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: Icon(entry.icon, color: entry.color, size: 22),
                ),
              ),
              SizedBox(width: space.x3),
              Expanded(
                child: Text(
                  description,
                  style: type.bodyMedium.copyWith(color: colors.onSurface),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(width: space.x2),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    amount,
                    style: type.labelLarge.copyWith(
                      color: colors.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: space.x1),
                  Text(
                    relative,
                    style: type.bodySmall.copyWith(color: colors.onSurfaceMuted),
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

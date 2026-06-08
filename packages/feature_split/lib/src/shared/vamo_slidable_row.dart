import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

/// Swipe edit/delete row with long-press a11y fallback (S38).
class VamoSlidableRow extends StatelessWidget {
  const VamoSlidableRow({
    super.key,
    required this.child,
    required this.editLabel,
    required this.deleteLabel,
    required this.deleteConfirmTitle,
    required this.deleteConfirmAction,
    required this.cancelLabel,
    this.onEdit,
    this.onDelete,
    this.startActions,
  });

  final Widget child;
  final String editLabel;
  final String deleteLabel;
  final String deleteConfirmTitle;
  final String deleteConfirmAction;
  final String cancelLabel;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  /// Optional custom start pane (e.g. member role actions).
  final List<SlidableAction>? startActions;

  Future<bool> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(deleteConfirmTitle),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(cancelLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(deleteConfirmAction),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _showA11yMenu(BuildContext context) async {
    final actions = <({String label, VoidCallback? action})>[];
    if (startActions != null) {
      for (final action in startActions!) {
        final label = action.label ?? '';
        final callback = action.onPressed;
        actions.add((
          label: label,
          action: callback == null ? null : () => callback(context),
        ));
      }
    }
    if (onEdit != null) {
      actions.add((label: editLabel, action: onEdit));
    }
    if (onDelete != null) {
      actions.add((
        label: deleteLabel,
        action: () async {
          if (await _confirmDelete(context)) onDelete!();
        },
      ));
    }
    if (actions.isEmpty) return;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final entry in actions)
              ListTile(
                title: Text(entry.label),
                onTap: () {
                  Navigator.pop(ctx);
                  entry.action?.call();
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.vamoColors;
    final hasDelete = onDelete != null;
    final hasEdit = onEdit != null;
    final hasStart = startActions != null && startActions!.isNotEmpty;
    if (!hasDelete && !hasEdit && !hasStart) return child;

    return Semantics(
      button: true,
      label: editLabel,
      child: Slidable(
        key: ValueKey(Object.hash(editLabel, deleteLabel, child.key)),
        groupTag: 'vamo-slidable',
        endActionPane: hasDelete
            ? ActionPane(
                motion: const DrawerMotion(),
                extentRatio: 0.28,
                children: [
                  SlidableAction(
                    onPressed: (_) async {
                      if (await _confirmDelete(context)) onDelete!();
                    },
                    backgroundColor: colors.error,
                    foregroundColor: colors.onPrimary,
                    icon: Icons.delete_outline,
                    label: deleteLabel,
                  ),
                ],
              )
            : null,
        startActionPane: () {
          final actions = <SlidableAction>[
            if (startActions != null) ...startActions!,
            if (hasEdit)
              SlidableAction(
                onPressed: (_) => onEdit!(),
                backgroundColor: colors.secondary,
                foregroundColor: colors.onSecondary,
                icon: Icons.edit_outlined,
                label: editLabel,
              ),
          ];
          if (actions.isEmpty) return null;
          return ActionPane(
            motion: const DrawerMotion(),
            extentRatio: 0.28 + (actions.length - 1) * 0.08,
            children: actions,
          );
        }(),
        child: GestureDetector(
          onLongPress: () => _showA11yMenu(context),
          child: child,
        ),
      ),
    );
  }
}

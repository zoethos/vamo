import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'trip_lifecycle_labels.dart';
import 'trip_lifecycle_menu.dart';
import 'trips_repository.dart';

/// Dialogs + RPC calls for lifecycle overflow actions (S17.1).
class TripLifecycleActions {
  TripLifecycleActions._();

  static Future<void> handleMenuAction({
    required BuildContext context,
    required WidgetRef ref,
    required String tripId,
    required TripLifecycleMenuAction action,
    required TripLifecycleLabels labels,
    required TripsRepository repo,
  }) async {
    switch (action) {
      case TripLifecycleMenuAction.markDone:
        await _confirmDone(context, ref, tripId, labels, repo);
      case TripLifecycleMenuAction.requestClose:
        await _confirmRequestClose(context, ref, tripId, labels, repo);
      case TripLifecycleMenuAction.cancelTrip:
        await _confirmCancel(context, ref, tripId, labels, repo);
    }
  }

  static Future<void> _confirmDone(
    BuildContext context,
    WidgetRef ref,
    String tripId,
    TripLifecycleLabels labels,
    TripsRepository repo,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(labels.markDoneTitle),
        content: Text(labels.markDoneBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(labels.notYet),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(labels.markDoneConfirm),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await _run(context, ref, () => repo.markTripMemberComplete(tripId));
    }
  }

  static Future<void> _confirmCancel(
    BuildContext context,
    WidgetRef ref,
    String tripId,
    TripLifecycleLabels labels,
    TripsRepository repo,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(labels.cancelTripTitle),
        content: Text(labels.cancelTripBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(labels.keepTrip),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(labels.cancelTrip),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await _run(context, ref, () => repo.cancelTrip(tripId));
    }
  }

  static Future<void> _confirmRequestClose(
    BuildContext context,
    WidgetRef ref,
    String tripId,
    TripLifecycleLabels labels,
    TripsRepository repo,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(labels.requestCloseTitle),
        content: Text(labels.requestCloseBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(labels.notYet),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(labels.requestCloseConfirm),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await _run(context, ref, () => repo.requestTripClose(tripId));
    }
  }

  static Future<void> confirmForceClose({
    required BuildContext context,
    required WidgetRef ref,
    required String tripId,
    required TripLifecycleLabels labels,
    required TripsRepository repo,
  }) async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(labels.closeAnywayTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(labels.closeAnywayBody),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: InputDecoration(labelText: labels.closeAnywayHint),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(labels.back),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(ctx, controller.text.trim() == labels.closeAnywayPhrase),
            child: Text(labels.closeTrip),
          ),
        ],
      ),
    );
    controller.dispose();
    if (ok == true && context.mounted) {
      await _run(context, ref, () => repo.forceCloseTrip(tripId));
    }
  }

  static Future<void> showObjectDialog({
    required BuildContext context,
    required WidgetRef ref,
    required String tripId,
    required TripLifecycleLabels labels,
    required TripsRepository repo,
  }) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(labels.objectTitle),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: labels.objectReasonLabel,
            hintText: labels.objectReasonHint,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(labels.back),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isEmpty) return;
              Navigator.pop(ctx, text);
            },
            child: Text(labels.submitObjection),
          ),
        ],
      ),
    );
    controller.dispose();
    if (reason != null && context.mounted) {
      await _run(
        context,
        ref,
        () => repo.objectToTripClose(tripId: tripId, reason: reason),
      );
    }
  }

  static Future<void> runLifecycleRpc({
    required BuildContext context,
    required WidgetRef ref,
    required Future<void> Function() action,
  }) =>
      _run(context, ref, action);

  static Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (e) {
      if (!context.mounted) return;
      showActionError(
        context,
        ref,
        screen: 'trip_home',
        action: 'lifecycle',
        error: e,
      );
    }
  }
}

String lifecycleMenuLabel(
  TripLifecycleMenuAction action,
  TripLifecycleLabels labels,
) {
  switch (action) {
    case TripLifecycleMenuAction.markDone:
      return labels.markDone;
    case TripLifecycleMenuAction.requestClose:
      return labels.requestClose;
    case TripLifecycleMenuAction.cancelTrip:
      return labels.cancelTrip;
  }
}

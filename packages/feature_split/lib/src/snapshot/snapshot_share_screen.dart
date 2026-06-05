import 'dart:io';

import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../capture/capture_models.dart';
import '../capture/capture_providers.dart';
import '../expenses/expense_models.dart';
import '../expenses/expenses_providers.dart';
import '../expenses/money_format.dart';
import '../trips/trip_format.dart';
import '../trips/trips_models.dart';
import '../trips/trips_providers.dart';
import 'snapshot_capture.dart';
import 'snapshot_card.dart';
import 'snapshot_models.dart';
import 'snapshot_themes.dart';

/// Slice 7 — preview branded card, rasterize to PNG, system share sheet.
class SnapshotShareScreen extends ConsumerStatefulWidget {
  const SnapshotShareScreen({super.key, required this.tripId});

  final String tripId;

  @override
  ConsumerState<SnapshotShareScreen> createState() =>
      _SnapshotShareScreenState();
}

class _SnapshotShareScreenState extends ConsumerState<SnapshotShareScreen> {
  final _boundaryKey = GlobalKey();
  bool _sharing = false;

  SnapshotCardData _compose({
    required TripDetail trip,
    required List<ExpenseSummary> expenses,
    required List<TripMemberView> members,
    required CaptureSnapshotHighlight capture,
  }) {
    return SnapshotCardData(
      tripId: widget.tripId,
      tripName: trip.name,
      destination: trip.destination,
      dateRange: formatTripDateRange(trip.startDate, trip.endDate),
      totalSpentCents: totalSpentBaseCents(
        expenses.map((e) => e.baseCents),
      ),
      baseCurrency: trip.baseCurrency,
      expenseCount: expenses.length,
      members: members
          .map((m) => SnapshotMemberAvatar(displayName: m.displayName))
          .toList(),
      capture: capture,
    );
  }

  Future<void> _share(
    BuildContext shareButtonContext,
    SnapshotThemePack theme,
  ) async {
    final boundary = _boundaryKey.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Card not ready — try again.')),
      );
      return;
    }

    setState(() => _sharing = true);
    try {
      final png = await captureRepaintBoundaryToPng(boundary);
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/vamo-snapshot-${widget.tripId.substring(0, 8)}.png',
      );
      await file.writeAsBytes(png);

      final shareOrigin = _shareOriginFor(shareButtonContext);
      final result = await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png')],
        text: 'Our trip on Vamo — split fairly, travel together.',
        subject: 'Trip snapshot',
        sharePositionOrigin: shareOrigin,
      );

      if (result.status == ShareResultStatus.success) {
        ref.read(analyticsProvider).capture(
              VamoEvent.snapshotShared,
              properties: {
                'trip_id': widget.tripId,
                'bytes': png.length,
                'theme_id': theme.id,
              },
            );
      }
    } catch (e) {
      if (!mounted) return;
      showActionError(
        context,
        ref,
        screen: 'snapshot',
        action: 'share_snapshot',
        error: e,
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  /// Required on iPad — `share_plus` crashes without an origin rect.
  Rect? _shareOriginFor(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    final offset = box.localToGlobal(Offset.zero);
    return offset & box.size;
  }

  @override
  Widget build(BuildContext context) {
    final trip = ref.watch(tripDetailProvider(widget.tripId));
    final expenses = ref.watch(tripExpensesProvider(widget.tripId));
    final members = ref.watch(tripMembersForExpenseProvider(widget.tripId));
    final capture = ref.watch(captureSnapshotHighlightProvider(widget.tripId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Share snapshot'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _sharing ? null : () => context.pop(),
        ),
      ),
      body: trip.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AppErrorState(
          screen: 'snapshot',
          message: formatActionFailureMessage(e),
          kind: classifyActionFailureKind(e),
          onRetry: () => ref.invalidate(tripDetailProvider(widget.tripId)),
        ),
        data: (detail) {
          if (detail == null) {
            return const Center(child: Text('Trip not found'));
          }

          return expenses.when(
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) => AppErrorState(
              screen: 'snapshot',
              message: formatActionFailureMessage(e),
              kind: classifyActionFailureKind(e),
              onRetry: () =>
                  ref.invalidate(tripExpensesProvider(widget.tripId)),
            ),
            data: (expenseList) => members.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => AppErrorState(
                screen: 'snapshot',
                message: formatActionFailureMessage(e),
                kind: classifyActionFailureKind(e),
                onRetry: () => ref.invalidate(
                  tripMembersForExpenseProvider(widget.tripId),
                ),
              ),
              data: (memberList) {
                final theme = SnapshotThemes.resolve(
                  destination: detail.destination,
                  tripName: detail.name,
                );
                final data = _compose(
                  trip: detail,
                  expenses: expenseList,
                  members: memberList,
                  capture: capture,
                );

                return ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text(
                      'A branded card for your group chat or social feed.',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: AppColors.muted),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Chip(
                        avatar: Icon(
                          Icons.palette_outlined,
                          size: 18,
                          color: theme.statPrimary,
                        ),
                        label: Text('${theme.label} theme'),
                        side: BorderSide(color: AppColors.muted.withValues(alpha: 0.3)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: RepaintBoundary(
                        key: _boundaryKey,
                        child: SnapshotBrandedCard(data: data, theme: theme),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      data.expenseCount == 0
                          ? 'Add expenses to show a total on the card.'
                          : 'Total: ${formatMoneyFromCents(data.totalSpentCents, data.baseCurrency)}',
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: AppColors.muted),
                    ),
                    const SizedBox(height: 28),
                    Builder(
                      builder: (buttonContext) => FilledButton.icon(
                      onPressed: _sharing ? null : () => _share(buttonContext, theme),
                      icon: _sharing
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.share_outlined),
                      label: const Text('Share image'),
                    ),
                    ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }
}

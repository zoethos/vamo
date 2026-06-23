import 'dart:io';

import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../expenses/money_format.dart';
import '../plan/plan_models.dart';
import '../plan/plan_type_visuals.dart';
import 'activity_models.dart';
import 'activity_repository.dart';

class ActivityScreenLabels {
  const ActivityScreenLabels({
    required this.title,
    this.subtitle = 'Across all your trips',
    required this.emptyTitle,
    required this.emptySubtitle,
    required this.loadError,
    required this.eventCreatedSubtitle,
    required this.eventRsvpSubtitle,
    required this.rsvpGoing,
    required this.rsvpMaybe,
    required this.rsvpDeclined,
    this.filterAll = 'All',
    this.filterMoney = 'Money',
    this.filterPlan = 'Plan',
    this.filterMembers = 'Members',
    this.filterMedia = 'Media',
  });

  final String title;
  final String subtitle;
  final String emptyTitle;
  final String emptySubtitle;
  final String loadError;
  final String eventCreatedSubtitle;
  final String Function(String status) eventRsvpSubtitle;
  final String rsvpGoing;
  final String rsvpMaybe;
  final String rsvpDeclined;
  final String filterAll;
  final String filterMoney;
  final String filterPlan;
  final String filterMembers;
  final String filterMedia;
}

/// Cross-trip chronological audit feed from local Drift data.
class ActivityScreen extends ConsumerStatefulWidget {
  const ActivityScreen({super.key, required this.labels});

  final ActivityScreenLabels labels;

  @override
  ConsumerState<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends ConsumerState<ActivityScreen> {
  ActivityFilter _filter = ActivityFilter.all;

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(activityFeedProvider);
    final colors = context.vamoColors;
    final type = context.vamoType;

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: feed.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => AppErrorState(
            screen: 'activity',
            message: widget.labels.loadError,
            onRetry: () => ref.invalidate(activityFeedProvider),
          ),
          data: (items) {
            final filtered = _filter == ActivityFilter.all
                ? items
                : items.where((item) => item.filter == _filter).toList();
            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding:
                        const EdgeInsetsDirectional.fromSTEB(24, 18, 24, 0),
                    child: _ActivityHeader(
                      title: widget.labels.title,
                      subtitle: widget.labels.subtitle,
                      type: type,
                      colors: colors,
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(top: 18),
                    child: _FilterBar(
                      selected: _filter,
                      labels: widget.labels,
                      onSelected: (filter) => setState(() => _filter = filter),
                    ),
                  ),
                ),
                if (filtered.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: AppEmptyState(
                      screen: 'activity',
                      icon: Icons.timeline_outlined,
                      title: widget.labels.emptyTitle,
                      subtitle: widget.labels.emptySubtitle,
                    ),
                  )
                else
                  _ActivityFeedSliver(items: filtered),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ActivityHeader extends StatelessWidget {
  const _ActivityHeader({
    required this.title,
    required this.subtitle,
    required this.type,
    required this.colors,
  });

  final String title;
  final String subtitle;
  final VamoTypeScale type;
  final VamoSemanticColors colors;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: type.display.copyWith(
                  color: colors.onBackground,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: type.bodyMedium.copyWith(color: colors.onSurfaceMuted),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Notifications',
          onPressed: () => context.push(AppRoutes.notifications),
          icon: Icon(Icons.notifications_none, color: colors.onBackground),
        ),
      ],
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.selected,
    required this.labels,
    required this.onSelected,
  });

  final ActivityFilter selected;
  final ActivityScreenLabels labels;
  final ValueChanged<ActivityFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    final filters = <(ActivityFilter, String)>[
      (ActivityFilter.all, labels.filterAll),
      (ActivityFilter.money, labels.filterMoney),
      (ActivityFilter.plan, labels.filterPlan),
      (ActivityFilter.members, labels.filterMembers),
      (ActivityFilter.media, labels.filterMedia),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 24),
      child: Row(
        children: [
          for (final entry in filters) ...[
            _FilterChip(
              label: entry.$2,
              selected: entry.$1 == selected,
              onTap: () => onSelected(entry.$1),
            ),
            const SizedBox(width: 10),
          ],
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.vamoColors;
    final type = context.vamoType;
    return Material(
      color: selected ? colors.onBackground : colors.surfaceMuted,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: 20,
            vertical: 10,
          ),
          child: Text(
            label,
            style: type.labelLarge.copyWith(
              color: selected ? colors.background : colors.onSurfaceMuted,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

class _ActivityFeedSliver extends StatelessWidget {
  const _ActivityFeedSliver({required this.items});

  final List<ActivityItem> items;

  @override
  Widget build(BuildContext context) {
    final grouped = groupActivityByDay(items);
    final days = grouped.keys.toList()..sort((a, b) => b.compareTo(a));
    final children = <Widget>[];
    for (final day in days) {
      final dayItems = grouped[day]!;
      children
        ..add(_DayHeader(day: day))
        ..addAll(dayItems.map((item) => _ActivityRow(item: item)));
    }
    return SliverPadding(
      padding: const EdgeInsetsDirectional.fromSTEB(24, 18, 24, 96),
      sliver: SliverList.list(children: children),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final colors = context.vamoColors;
    final type = context.vamoType;
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: 14, bottom: 10),
      child: Text(
        _dayLabel(day),
        style: type.labelLarge.copyWith(
          color: colors.onSurfaceMuted,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  String _dayLabel(DateTime day) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    if (day == today) return 'Today';
    if (day == yesterday) return 'Yesterday';
    final startOfYear = DateTime(today.year);
    if (day.isBefore(startOfYear)) return DateFormat.yMMMd().format(day);
    return DateFormat.MMMd().format(day);
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.item});

  final ActivityItem item;

  @override
  Widget build(BuildContext context) {
    final colors = context.vamoColors;
    final type = context.vamoType;
    final accent = _accentFor(item);
    return Semantics(
      button: true,
      label: '${item.title}. ${item.tripName}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => context.push(item.route),
          child: Padding(
            padding: const EdgeInsetsDirectional.symmetric(vertical: 10),
            child: Row(
              children: [
                _TripThumbnail(item: item, accent: accent),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: type.titleMedium.copyWith(
                          color: colors.onSurface,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${item.tripName} · ${_relativeTime(item.occurredAt)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: type.bodySmall.copyWith(
                          color: colors.onSurfaceMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (item.hasAmount) ...[
                  const SizedBox(width: 10),
                  _AmountText(item: item),
                ],
                const SizedBox(width: 6),
                Icon(
                  Icons.chevron_right,
                  color: colors.divider,
                  size: 24,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _accentFor(ActivityItem item) {
    if (item.planKind != null) {
      return visualForPlanKind(PlanItemKind.parse(item.planKind)).accent;
    }
    if (item.expenseCategory != null) {
      return CategoryCatalog.resolve(item.expenseCategory).color;
    }
    return switch (item.kind) {
      ActivityKind.expenseAdded => VamoPlanTypeColors.train,
      ActivityKind.settlement => VamoPlanTypeColors.train,
      ActivityKind.memberJoined => VamoPlanTypeColors.lodging,
      ActivityKind.planItemAdded => VamoPlanTypeColors.visit,
      ActivityKind.planRsvp => VamoPlanTypeColors.visit,
      ActivityKind.noteAdded => VamoPlanTypeColors.other,
      ActivityKind.photosAdded => VamoPlanTypeColors.flight,
      ActivityKind.videosAdded => VamoPlanTypeColors.flight,
      ActivityKind.lifecycle => VamoPlanTypeColors.lodging,
    };
  }
}

class _TripThumbnail extends StatelessWidget {
  const _TripThumbnail({required this.item, required this.accent});

  final ActivityItem item;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final imagePath = item.tripImagePath;
    return SizedBox(
      width: 60,
      height: 60,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(15),
              child: _TripImage(path: imagePath, accent: accent),
            ),
          ),
          PositionedDirectional(
            end: -3,
            bottom: -3,
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: accent,
                shape: BoxShape.circle,
                border:
                    Border.all(color: context.vamoColors.background, width: 3),
              ),
              child: Icon(_iconFor(item), color: Colors.white, size: 16),
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconFor(ActivityItem item) {
    if (item.planKind != null) {
      return visualForPlanKind(PlanItemKind.parse(item.planKind)).icon;
    }
    if (item.expenseCategory != null) {
      return CategoryCatalog.resolve(item.expenseCategory).icon;
    }
    return switch (item.kind) {
      ActivityKind.expenseAdded => Icons.receipt_long_outlined,
      ActivityKind.settlement => Icons.payments_outlined,
      ActivityKind.memberJoined => Icons.group_add_outlined,
      ActivityKind.planItemAdded => Icons.place_outlined,
      ActivityKind.planRsvp => Icons.event_available_outlined,
      ActivityKind.noteAdded => Icons.sticky_note_2_outlined,
      ActivityKind.photosAdded => Icons.photo_camera_outlined,
      ActivityKind.videosAdded => Icons.videocam_outlined,
      ActivityKind.lifecycle => Icons.flag_outlined,
    };
  }
}

class _TripImage extends StatelessWidget {
  const _TripImage({required this.path, required this.accent});

  final String? path;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final colors = context.vamoColors;
    final path = this.path;
    if (path != null && path.startsWith('http')) {
      return Image.network(path, fit: BoxFit.cover);
    }
    if (path != null && File(path).existsSync()) {
      return Image.file(File(path), fit: BoxFit.cover);
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [
            accent.withValues(alpha: 0.85),
            colors.primary.withValues(alpha: 0.82),
          ],
        ),
      ),
    );
  }
}

class _AmountText extends StatelessWidget {
  const _AmountText({required this.item});

  final ActivityItem item;

  @override
  Widget build(BuildContext context) {
    final colors = context.vamoColors;
    final type = context.vamoType;
    final cents = item.amountCents!;
    final currency = item.currency!;
    final prefix = switch (item.amountTone) {
      ActivityAmountTone.positive => '+',
      ActivityAmountTone.negative => 'you owe ',
      ActivityAmountTone.neutral => '',
    };
    final text = '$prefix${formatMoneyFromCents(cents, currency)}';
    final color = switch (item.amountTone) {
      ActivityAmountTone.positive => colors.success,
      ActivityAmountTone.negative => colors.error,
      ActivityAmountTone.neutral => colors.onSurfaceMuted,
    };
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 116),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.end,
        style: type.labelLarge.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

String _relativeTime(DateTime occurredAt) {
  final now = DateTime.now();
  final local = occurredAt.toLocal();
  final elapsed = now.difference(local);
  if (elapsed.inMinutes < 1) return 'now';
  if (elapsed.inHours < 1) return '${elapsed.inMinutes}m ago';
  if (elapsed.inHours < 24) return '${elapsed.inHours}h ago';
  if (elapsed.inDays < 7) return DateFormat.E().format(local);
  return DateFormat.MMMd().format(local);
}

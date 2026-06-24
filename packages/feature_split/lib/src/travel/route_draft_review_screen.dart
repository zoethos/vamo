import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../plan/plan_models.dart';
import '../plan/plan_repository.dart';
import 'advanced_travel_labels.dart';
import 'route_draft.dart';

typedef RouteDraftCommitOverride = Future<void> Function(
  List<RouteDraftItem> acceptedItems,
);

/// Reviews an AI-drafted route before it becomes ordinary Plan items.
///
/// The AI result is still a proposal here: the user can keep, skip, or create
/// an empty trip before accepted stops are persisted via [PlanRepository].
class RouteDraftReviewScreen extends ConsumerStatefulWidget {
  const RouteDraftReviewScreen({
    super.key,
    required this.tripId,
    required this.draft,
    required this.labels,
    this.title,
    this.subtitle,
    this.initiallySkippedIndexes = const <int>{},
    @visibleForTesting this.commitOverride,
  });

  final String tripId;
  final RouteDraft draft;
  final AdvancedTravelLabels labels;
  final String? title;
  final String? subtitle;

  /// Test/preview hook for reference states where AI already marked some stops
  /// as less preferred. Production drafts currently accept every stop by
  /// default because the Edge Function payload has no recommendation flag.
  final Set<int> initiallySkippedIndexes;

  @visibleForTesting
  final RouteDraftCommitOverride? commitOverride;

  @override
  ConsumerState<RouteDraftReviewScreen> createState() =>
      _RouteDraftReviewScreenState();
}

class _RouteDraftReviewScreenState
    extends ConsumerState<RouteDraftReviewScreen> {
  late final Set<int> _accepted;
  bool _committing = false;

  @override
  void initState() {
    super.initState();
    _accepted = {
      for (var i = 0; i < widget.draft.items.length; i++)
        if (!widget.initiallySkippedIndexes.contains(i)) i,
    };
  }

  void _setAccepted(int index, bool accepted) {
    if (_committing) return;
    setState(() {
      if (accepted) {
        _accepted.add(index);
      } else {
        _accepted.remove(index);
      }
    });
  }

  void _keepAll() {
    if (_committing) return;
    setState(() {
      _accepted
        ..clear()
        ..addAll(Iterable<int>.generate(widget.draft.items.length));
    });
  }

  void _skipAll() {
    if (_committing) return;
    setState(_accepted.clear);
  }

  List<RouteDraftItem> _acceptedItemsInOrder() => [
        for (var i = 0; i < widget.draft.items.length; i++)
          if (_accepted.contains(i)) widget.draft.items[i],
      ];

  Future<void> _commit() async {
    setState(() => _committing = true);
    final acceptedItems = _acceptedItemsInOrder();
    try {
      final override = widget.commitOverride;
      if (override != null) {
        await override(acceptedItems);
      } else {
        final repo = ref.read(planRepositoryProvider);
        for (final item in acceptedItems) {
          await repo.addPlanItem(item.toPlanItemInput(widget.tripId));
        }
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      showActionError(
        context,
        ref,
        screen: 'route_draft_review',
        action: 'commit_draft',
        error: error,
      );
      setState(() => _committing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.draft.items;
    final title = _nonEmpty(widget.title) ?? widget.labels.reviewTitle;
    final subtitle = _nonEmpty(widget.subtitle) ?? widget.labels.reviewSubtitle;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: VamoTravelTokens.appBg,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: VamoTravelTokens.appBg,
        body: Column(
          children: [
            _ProposalHero(
              title: title,
              subtitle: subtitle,
              onBack:
                  _committing ? null : () => Navigator.of(context).pop(false),
            ),
            _AiIntro(totalStops: items.length),
            _ProposalCountBar(
              acceptedCount: _accepted.length,
              totalCount: items.length,
              onKeepAll: items.isEmpty ? null : _keepAll,
              onSkipAll: items.isEmpty ? null : _skipAll,
            ),
            Expanded(
              child: items.isEmpty
                  ? _EmptyDraft(message: widget.labels.reviewEmpty)
                  : _ProposalList(
                      items: items,
                      accepted: _accepted,
                      warnings: widget.draft.warnings,
                      questions: widget.draft.unresolvedQuestions,
                      labels: widget.labels,
                      onToggle: _setAccepted,
                    ),
            ),
            _ProposalFooter(
              acceptedCount: _accepted.length,
              committing: _committing,
              onCreate: _commit,
              onStartEmpty:
                  _committing ? null : () => Navigator.of(context).pop(false),
              committingLabel: widget.labels.reviewCommitting,
            ),
          ],
        ),
      ),
    );
  }
}

String? _nonEmpty(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

class _ProposalHero extends StatelessWidget {
  const _ProposalHero({
    required this.title,
    required this.subtitle,
    required this.onBack,
  });

  final String title;
  final String subtitle;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    return SizedBox(
      height: 168 + topInset,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFFF8A76),
                  Color(0xFFFFB25F),
                  Color(0xFF7D3D73),
                  Color(0xFF172033),
                ],
                stops: [0, 0.42, 0.76, 1],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.04),
                  Colors.black.withValues(alpha: 0.10),
                  Colors.black.withValues(alpha: 0.55),
                ],
                stops: const [0, 0.52, 1],
              ),
            ),
          ),
          Positioned(
            left: 14,
            top: topInset + 12,
            child: _HeroIconButton(
              icon: Icons.chevron_left,
              label: 'Back',
              onTap: onBack,
            ),
          ),
          Positioned(
            right: 14,
            top: topInset + 12,
            child: const _BackdropBadge(),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 18,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    height: 1.05,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.92),
                    fontSize: 13,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroIconButton extends StatelessWidget {
  const _HeroIconButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Opacity(
          opacity: onTap == null ? 0.55 : 1,
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.24),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
        ),
      ),
    );
  }
}

class _BackdropBadge extends StatelessWidget {
  const _BackdropBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome, color: Colors.white, size: 15),
          SizedBox(width: 6),
          Text(
            'AI backdrop',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _AiIntro extends StatelessWidget {
  const _AiIntro({required this.totalStops});

  final int totalStops;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: VamoTravelTokens.surface,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.auto_awesome,
            color: VamoTravelTokens.plum,
            size: 23,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              'AI found $totalStops stops worth visiting.\n'
              'Keep what you like — skip the rest.',
              style: const TextStyle(
                color: VamoTravelTokens.inkSoft,
                fontSize: 12.5,
                height: 1.28,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProposalCountBar extends StatelessWidget {
  const _ProposalCountBar({
    required this.acceptedCount,
    required this.totalCount,
    required this.onKeepAll,
    required this.onSkipAll,
  });

  final int acceptedCount;
  final int totalCount;
  final VoidCallback? onKeepAll;
  final VoidCallback? onSkipAll;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: VamoTravelTokens.surface,
        border: Border(
          top: BorderSide(color: VamoTravelTokens.hairline),
          bottom: BorderSide(color: VamoTravelTokens.hairline),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 9, 16, 9),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$acceptedCount of $totalCount kept',
              style: const TextStyle(
                color: VamoTravelTokens.ink,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          _InlineAction(label: 'Keep all', onTap: onKeepAll),
          const Text(
            ' / ',
            style: TextStyle(
              color: VamoTravelTokens.plum,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          _InlineAction(label: 'Skip all', onTap: onSkipAll),
        ],
      ),
    );
  }
}

class _InlineAction extends StatelessWidget {
  const _InlineAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Opacity(
          opacity: onTap == null ? 0.45 : 1,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              label,
              style: const TextStyle(
                color: VamoTravelTokens.plum,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProposalList extends StatelessWidget {
  const _ProposalList({
    required this.items,
    required this.accepted,
    required this.warnings,
    required this.questions,
    required this.labels,
    required this.onToggle,
  });

  final List<RouteDraftItem> items;
  final Set<int> accepted;
  final List<String> warnings;
  final List<String> questions;
  final AdvancedTravelLabels labels;
  final void Function(int index, bool accepted) onToggle;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toString();
    final groups = _groupByDay(items, locale);
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      physics: const BouncingScrollPhysics(),
      children: [
        for (final group in groups) ...[
          _DayHeader(label: group.label),
          _DayCard(
            itemIndexes: group.indexes,
            items: items,
            accepted: accepted,
            onToggle: onToggle,
          ),
        ],
        if (warnings.isNotEmpty)
          _DraftNoteBlock(
            title: labels.reviewWarningsTitle,
            notes: warnings,
            icon: Icons.warning_amber_rounded,
            color: VamoTravelTokens.carOrange,
          ),
        if (questions.isNotEmpty)
          _DraftNoteBlock(
            title: labels.reviewQuestionsTitle,
            notes: questions,
            icon: Icons.help_outline,
            color: VamoTravelTokens.sky,
          ),
      ],
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 5, 6, 3),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: VamoTravelTokens.slate,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _DayCard extends StatelessWidget {
  const _DayCard({
    required this.itemIndexes,
    required this.items,
    required this.accepted,
    required this.onToggle,
  });

  final List<int> itemIndexes;
  final List<RouteDraftItem> items;
  final Set<int> accepted;
  final void Function(int index, bool accepted) onToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: VamoTravelTokens.surface,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: VamoTravelTokens.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var row = 0; row < itemIndexes.length; row++) ...[
            _DraftStopRow(
              item: items[itemIndexes[row]],
              accepted: accepted.contains(itemIndexes[row]),
              onTap: () => onToggle(
                itemIndexes[row],
                !accepted.contains(itemIndexes[row]),
              ),
            ),
            if (row != itemIndexes.length - 1)
              const Divider(
                height: 1,
                indent: 58,
                color: VamoTravelTokens.hairline,
              ),
          ],
        ],
      ),
    );
  }
}

class _DraftStopRow extends StatelessWidget {
  const _DraftStopRow({
    required this.item,
    required this.accepted,
    required this.onTap,
  });

  final RouteDraftItem item;
  final bool accepted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final visual = _visualFor(item);
    final textOpacity = accepted ? 1.0 : 0.44;
    return Semantics(
      button: true,
      selected: accepted,
      label: '${accepted ? 'Kept' : 'Skipped'} ${item.title}',
      child: Material(
        color: VamoTravelTokens.surface,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 55),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 10, 6),
              child: Row(
                children: [
                  Opacity(
                    opacity: accepted ? 1 : 0.46,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: visual.accent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(visual.icon, color: Colors.white, size: 21),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Opacity(
                      opacity: textOpacity,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: VamoTravelTokens.ink,
                              fontSize: 13.5,
                              height: 1.15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 3),
                          _MetaText(meta: _metaFor(item)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _SelectionMark(accepted: accepted),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MetaText extends StatelessWidget {
  const _MetaText({required this.meta});

  final String meta;

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style.merge(
          const TextStyle(
            color: VamoTravelTokens.slate,
            fontSize: 12,
            height: 1.1,
            fontWeight: FontWeight.w500,
          ),
        );
    final arrowIndex = meta.indexOf('→');
    if (arrowIndex == -1) {
      return Text(
        meta,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }
    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: style,
        children: [
          TextSpan(text: meta.substring(0, arrowIndex)),
          const WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 2),
              child: Icon(
                Icons.arrow_forward,
                color: VamoTravelTokens.slate,
                size: 12,
              ),
            ),
          ),
          TextSpan(text: meta.substring(arrowIndex + 1)),
        ],
      ),
    );
  }
}

class _SelectionMark extends StatelessWidget {
  const _SelectionMark({required this.accepted});

  final bool accepted;

  @override
  Widget build(BuildContext context) {
    if (accepted) {
      return Container(
        width: 26,
        height: 26,
        decoration: const BoxDecoration(
          color: Color(0xFF63B52F),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.check, color: Colors.white, size: 19),
      );
    }
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: VamoTravelTokens.surface,
        shape: BoxShape.circle,
        border: Border.all(color: VamoTravelTokens.slate, width: 1.2),
      ),
      child: const Icon(Icons.add, color: VamoTravelTokens.inkSoft, size: 17),
    );
  }
}

class _ProposalFooter extends StatelessWidget {
  const _ProposalFooter({
    required this.acceptedCount,
    required this.committing,
    required this.onCreate,
    required this.onStartEmpty,
    required this.committingLabel,
  });

  final int acceptedCount;
  final bool committing;
  final VoidCallback onCreate;
  final VoidCallback? onStartEmpty;
  final String committingLabel;

  @override
  Widget build(BuildContext context) {
    final cta = acceptedCount == 0
        ? 'Create empty trip'
        : 'Create trip · $acceptedCount stops';
    final ctaStyle = Theme.of(context).textTheme.labelLarge?.copyWith(
              color: VamoTravelTokens.ink,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ) ??
        const TextStyle(
          color: VamoTravelTokens.ink,
          fontSize: 16,
          fontWeight: FontWeight.w800,
        );
    return Container(
      color: VamoTravelTokens.appBg,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: committing ? null : onCreate,
                style: FilledButton.styleFrom(
                  backgroundColor: VamoTravelTokens.lime,
                  foregroundColor: VamoTravelTokens.ink,
                  disabledBackgroundColor:
                      VamoTravelTokens.lime.withValues(alpha: 0.48),
                  disabledForegroundColor:
                      VamoTravelTokens.ink.withValues(alpha: 0.62),
                  minimumSize: const Size.fromHeight(56),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                  shadowColor: Colors.transparent,
                ),
                child:
                    Text(committing ? committingLabel : cta, style: ctaStyle),
              ),
            ),
            const SizedBox(height: 10),
            _StartEmptyLink(onStartEmpty: onStartEmpty),
          ],
        ),
      ),
    );
  }
}

class _StartEmptyLink extends StatelessWidget {
  const _StartEmptyLink({required this.onStartEmpty});

  final VoidCallback? onStartEmpty;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Text(
          'or ',
          style: TextStyle(
            color: VamoTravelTokens.slate,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        Semantics(
          button: true,
          label: 'Start empty',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onStartEmpty,
            child: Opacity(
              opacity: onStartEmpty == null ? 0.45 : 1,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 3),
                child: Text(
                  'start empty',
                  style: TextStyle(
                    color: VamoTravelTokens.plum,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
        ),
        const Text(
          ' — add stops yourself',
          style: TextStyle(
            color: VamoTravelTokens.slate,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _EmptyDraft extends StatelessWidget {
  const _EmptyDraft({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: VamoTravelTokens.slate,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _DraftNoteBlock extends StatelessWidget {
  const _DraftNoteBlock({
    required this.title,
    required this.notes,
    required this.icon,
    required this.color,
  });

  final String title;
  final List<String> notes;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: VamoTravelTokens.surface,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: VamoTravelTokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 7),
              Text(
                title,
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final note in notes)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                note,
                style: const TextStyle(
                  color: VamoTravelTokens.slate,
                  fontSize: 12.5,
                  height: 1.25,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DraftDayGroup {
  const _DraftDayGroup({required this.label, required this.indexes});

  final String label;
  final List<int> indexes;
}

List<_DraftDayGroup> _groupByDay(List<RouteDraftItem> items, String locale) {
  final groups = <_DraftDayGroup>[];
  String? currentKey;
  var dayNumber = 0;
  for (var i = 0; i < items.length; i++) {
    final date = items[i].startsAt ?? items[i].endsAt;
    final key = date == null
        ? 'undated'
        : DateFormat('yyyy-MM-dd', locale).format(date);
    if (key != currentKey) {
      currentKey = key;
      if (date != null) dayNumber++;
      groups.add(
        _DraftDayGroup(
          label: date == null
              ? 'SUGGESTED STOPS'
              : 'DAY $dayNumber · ${DateFormat('MMM d', locale).format(date).toUpperCase()}',
          indexes: <int>[],
        ),
      );
    }
    groups.last.indexes.add(i);
  }
  return groups;
}

String _metaFor(RouteDraftItem item) {
  final notes = _nonEmpty(item.notes);
  if (notes != null) return notes;
  return switch (item.kind) {
    PlanItemKind.lodging => 'Lodging',
    PlanItemKind.flight => 'Flight',
    PlanItemKind.train => 'Train',
    PlanItemKind.transfer => 'Transport',
    PlanItemKind.activity => 'Activity',
    PlanItemKind.visit => 'Visit',
    PlanItemKind.other => 'Stop',
  };
}

class _StopVisual {
  const _StopVisual({required this.accent, required this.icon});

  final Color accent;
  final IconData icon;
}

_StopVisual _visualFor(RouteDraftItem item) {
  final text = '${item.title} ${item.notes ?? ''}'.toLowerCase();
  if (text.contains('restaurant') ||
      text.contains('lunch') ||
      text.contains('dinner')) {
    return const _StopVisual(
      accent: VamoTravelTokens.carOrange,
      icon: Icons.restaurant,
    );
  }
  if (text.contains('ferry') ||
      text.contains('boat') ||
      item.transferSubtype != null) {
    return const _StopVisual(
      accent: VamoTravelTokens.carOrange,
      icon: Icons.directions_boat,
    );
  }
  if (text.contains('hike') || text.contains('path of the gods')) {
    return const _StopVisual(
      accent: VamoTravelTokens.jade,
      icon: Icons.hiking,
    );
  }
  if (text.contains('villa') ||
      text.contains('garden') ||
      text.contains('rufolo')) {
    return const _StopVisual(
      accent: VamoTravelTokens.plum,
      icon: Icons.local_florist,
    );
  }
  return switch (item.kind) {
    PlanItemKind.lodging => const _StopVisual(
        accent: VamoTravelTokens.plum,
        icon: Icons.bed,
      ),
    PlanItemKind.flight => const _StopVisual(
        accent: VamoTravelTokens.sky,
        icon: Icons.flight,
      ),
    PlanItemKind.train => const _StopVisual(
        accent: VamoTravelTokens.jadeBright,
        icon: Icons.train,
      ),
    PlanItemKind.transfer => const _StopVisual(
        accent: VamoTravelTokens.carOrange,
        icon: Icons.sync_alt,
      ),
    PlanItemKind.activity => const _StopVisual(
        accent: VamoTravelTokens.jade,
        icon: Icons.directions_walk,
      ),
    PlanItemKind.visit => const _StopVisual(
        accent: VamoTravelTokens.coral,
        icon: Icons.account_balance,
      ),
    PlanItemKind.other => const _StopVisual(
        accent: VamoTravelTokens.slate,
        icon: Icons.place,
      ),
  };
}

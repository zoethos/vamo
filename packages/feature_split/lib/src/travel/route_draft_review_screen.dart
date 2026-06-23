import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../plan/plan_models.dart';
import '../plan/plan_repository.dart';
import 'advanced_travel_labels.dart';
import 'route_draft.dart';

/// Reviews an AI-drafted route before it becomes ordinary Plan items. Every
/// stop is accepted by default; the user trims, then commits the accepted ones
/// via [PlanRepository.addPlanItem]. The draft is a proposal until this screen.
class RouteDraftReviewScreen extends ConsumerStatefulWidget {
  const RouteDraftReviewScreen({
    super.key,
    required this.tripId,
    required this.draft,
    required this.labels,
  });

  final String tripId;
  final RouteDraft draft;
  final AdvancedTravelLabels labels;

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
    _accepted = {for (var i = 0; i < widget.draft.items.length; i++) i};
  }

  Future<void> _commit() async {
    setState(() => _committing = true);
    final repo = ref.read(planRepositoryProvider);
    try {
      for (var i = 0; i < widget.draft.items.length; i++) {
        if (!_accepted.contains(i)) continue;
        await repo.addPlanItem(
          widget.draft.items[i].toPlanItemInput(widget.tripId),
        );
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
    final labels = widget.labels;
    final colors = context.vamoColors;
    final textTheme = Theme.of(context).textTheme;
    final locale = Localizations.localeOf(context).toString();
    final items = widget.draft.items;

    return Scaffold(
      appBar: AppBar(title: Text(labels.reviewTitle)),
      body: items.isEmpty
          ? Center(
              child: Text(
                labels.reviewEmpty,
                style: textTheme.bodyLarge?.copyWith(color: colors.onSurfaceMuted),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
              children: [
                Text(
                  labels.reviewSubtitle,
                  style: textTheme.bodyMedium
                      ?.copyWith(color: colors.onSurfaceMuted),
                ),
                const SizedBox(height: 12),
                for (var i = 0; i < items.length; i++)
                  _DraftItemTile(
                    item: items[i],
                    accepted: _accepted.contains(i),
                    locale: locale,
                    onChanged: _committing
                        ? null
                        : (on) => setState(() {
                              if (on) {
                                _accepted.add(i);
                              } else {
                                _accepted.remove(i);
                              }
                            }),
                  ),
                if (widget.draft.warnings.isNotEmpty)
                  _NoteBlock(
                    title: labels.reviewWarningsTitle,
                    notes: widget.draft.warnings,
                    icon: Icons.warning_amber_rounded,
                    color: colors.warning,
                  ),
                if (widget.draft.unresolvedQuestions.isNotEmpty)
                  _NoteBlock(
                    title: labels.reviewQuestionsTitle,
                    notes: widget.draft.unresolvedQuestions,
                    icon: Icons.help_outline,
                    color: colors.info,
                  ),
              ],
            ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed:
                    _committing ? null : () => Navigator.of(context).pop(false),
                child: Text(labels.reviewSkip),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: FilledButton(
                onPressed: (_committing || _accepted.isEmpty) ? null : _commit,
                style: FilledButton.styleFrom(
                  backgroundColor: colors.action,
                  foregroundColor: colors.onAction,
                  minimumSize: const Size.fromHeight(52),
                ),
                child: Text(
                  _committing
                      ? labels.reviewCommitting
                      : '${labels.reviewAddToPlan} (${_accepted.length})',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Color _kindColor(PlanItemKind kind) => switch (kind) {
      PlanItemKind.train => VamoPlanTypeColors.train,
      PlanItemKind.flight => VamoPlanTypeColors.flight,
      PlanItemKind.transfer => VamoPlanTypeColors.transfer,
      PlanItemKind.lodging => VamoPlanTypeColors.lodging,
      PlanItemKind.visit ||
      PlanItemKind.activity =>
        VamoPlanTypeColors.visit,
      PlanItemKind.other => VamoPlanTypeColors.other,
    };

String? _dateSummary(RouteDraftItem item, String locale) {
  final fmt = DateFormat.MMMd(locale);
  final s = item.startsAt;
  final e = item.endsAt;
  if (s == null && e == null) return null;
  if (s != null && e != null && s != e) {
    return '${fmt.format(s)} – ${fmt.format(e)}';
  }
  return fmt.format((s ?? e)!);
}

class _DraftItemTile extends StatelessWidget {
  const _DraftItemTile({
    required this.item,
    required this.accepted,
    required this.locale,
    required this.onChanged,
  });

  final RouteDraftItem item;
  final bool accepted;
  final String locale;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.vamoColors;
    final textTheme = Theme.of(context).textTheme;
    final color = _kindColor(item.kind);
    final date = _dateSummary(item, locale);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: CheckboxListTile(
        value: accepted,
        onChanged: onChanged == null ? null : (v) => onChanged!(v ?? false),
        controlAffinity: ListTileControlAffinity.trailing,
        secondary: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(item.kind.icon, color: color, size: 20),
        ),
        title: Text(
          item.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: textTheme.titleMedium?.copyWith(
            color: colors.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: date == null
            ? null
            : Text(
                date,
                style: textTheme.bodySmall
                    ?.copyWith(color: colors.onSurfaceMuted),
              ),
      ),
    );
  }
}

class _NoteBlock extends StatelessWidget {
  const _NoteBlock({
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
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Text(
                title,
                style: textTheme.titleSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (final note in notes)
            Padding(
              padding: const EdgeInsets.only(left: 24, bottom: 2),
              child: Text(
                '• $note',
                style: textTheme.bodySmall
                    ?.copyWith(color: context.vamoColors.onSurfaceMuted),
              ),
            ),
        ],
      ),
    );
  }
}

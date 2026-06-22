/// User-facing strings for the Trip Map screen.
///
/// Defaults are English. Trip Map is a new P0 surface, so strings start here
/// and can be promoted to the app's gen-l10n ARBs in a follow-up by mapping
/// these fields in `SplitLabels.tripMap(l10n)` — no call sites change.
class TripMapLabels {
  const TripMapLabels({
    this.title = 'Map',
    this.loadError = "Couldn't load the map.",
    this.emptyOverlay = 'Your journey appears here as you go.',
    this.allDays = 'All days',
    this.dayLabel = _defaultDayLabel,
    this.visitKind = 'Visit',
    this.expenseKind = 'Expense',
    this.memoryKind = 'Memory',
    this.untitledMoment = 'Untitled',
  });

  final String title;
  final String loadError;
  final String emptyOverlay;
  final String allDays;

  /// `(day, total) -> "Day 2 of 7"`.
  final String Function(int day, int total) dayLabel;

  final String visitKind;
  final String expenseKind;
  final String memoryKind;
  final String untitledMoment;

  static String _defaultDayLabel(int day, int total) => 'Day $day of $total';
}

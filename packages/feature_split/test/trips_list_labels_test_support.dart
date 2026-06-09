import 'package:feature_split/src/trips/trips_list_screen.dart';

final testTripsListLabels = TripsListScreenLabels(
  title: 'Your trips',
  emptyTitle: 'No trips yet',
  emptySubtitle: 'Tap + to start one.',
  emptyUpcomingTitle: 'No upcoming trips',
  emptyPastTitle: 'No past trips',
  syncPendingLabel: (count) => '$count waiting',
  syncSubtitle: 'Will upload when online',
  filterAll: 'All',
  filterUpcoming: 'Upcoming',
  filterPast: 'Past',
  filterDrafts: 'Drafts',
  loadError: 'Could not load trips.',
  syncError: 'Could not sync trips.',
  sectionUpcoming: 'Upcoming',
  sectionPast: 'Past',
  participants: (count) => '$count Vamigos',
  notificationsTooltip: 'Notifications',
  notificationsUnreadBadge: (count) => '$count unread',
  createTripTooltip: 'Create trip',
);

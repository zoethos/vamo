enum OfflinePackStatus {
  ready('ready'),
  syncing('syncing'),
  stale('stale'),
  failed('failed'),
  partial('partial');

  const OfflinePackStatus(this.value);
  final String value;

  static OfflinePackStatus parse(String value) {
    return OfflinePackStatus.values.firstWhere(
      (status) => status.value == value,
      orElse: () => OfflinePackStatus.failed,
    );
  }
}

enum OfflinePackTier {
  essentials('essentials');

  const OfflinePackTier(this.value);
  final String value;

  static OfflinePackTier parse(String value) {
    return OfflinePackTier.values.firstWhere(
      (tier) => tier.value == value,
      orElse: () => OfflinePackTier.essentials,
    );
  }
}

enum OfflinePackScope {
  trip('trip'),
  members('members'),
  planItems('plan_items'),
  checklists('checklists'),
  rsvps('rsvps'),
  places('places'),
  fxRates('fx_rates'),
  balances('balances'),
  pendingOutbox('pending_outbox'),
  mapTiles('map_tiles');

  const OfflinePackScope(this.value);
  final String value;
}

class OfflinePackRowCounts {
  const OfflinePackRowCounts({
    this.trips = 0,
    this.members = 0,
    this.planItems = 0,
    this.checklists = 0,
    this.rsvps = 0,
    this.places = 0,
    this.fxRates = 0,
    this.expenses = 0,
    this.expenseShares = 0,
    this.settlements = 0,
  });

  final int trips;
  final int members;
  final int planItems;
  final int checklists;
  final int rsvps;
  final int places;
  final int fxRates;
  final int expenses;
  final int expenseShares;
  final int settlements;

  int get totalRows =>
      trips +
      members +
      planItems +
      checklists +
      rsvps +
      places +
      fxRates +
      expenses +
      expenseShares +
      settlements;

  Map<String, int> toJson() => {
        'trips': trips,
        'members': members,
        'plan_items': planItems,
        'checklists': checklists,
        'rsvps': rsvps,
        'places': places,
        'fx_rates': fxRates,
        'expenses': expenses,
        'expense_shares': expenseShares,
        'settlements': settlements,
      };

  static OfflinePackRowCounts fromJson(Map<String, Object?> json) {
    return OfflinePackRowCounts(
      trips: _intValue(json['trips']),
      members: _intValue(json['members']),
      planItems: _intValue(json['plan_items']),
      checklists: _intValue(json['checklists']),
      rsvps: _intValue(json['rsvps']),
      places: _intValue(json['places']),
      fxRates: _intValue(json['fx_rates']),
      expenses: _intValue(json['expenses']),
      expenseShares: _intValue(json['expense_shares']),
      settlements: _intValue(json['settlements']),
    );
  }
}

class OfflinePackManifest {
  const OfflinePackManifest({
    required this.tripId,
    required this.tier,
    required this.status,
    required this.lastUpdatedAt,
    required this.rowCounts,
    this.missingScopes = const [],
    this.staleReasons = const [],
    this.pendingOutboxCount = 0,
    this.storageBytes = 0,
    this.secureSnapshotRef,
    this.lastError,
    this.evictionPinned = false,
    this.lastAccessedAt,
  });

  final String tripId;
  final OfflinePackTier tier;
  final OfflinePackStatus status;
  final DateTime? lastUpdatedAt;
  final OfflinePackRowCounts rowCounts;
  final List<OfflinePackScope> missingScopes;
  final List<String> staleReasons;
  final int pendingOutboxCount;
  final int storageBytes;
  final String? secureSnapshotRef;
  final String? lastError;
  final bool evictionPinned;
  final DateTime? lastAccessedAt;

  bool get isUsableOffline =>
      status == OfflinePackStatus.ready ||
      status == OfflinePackStatus.stale ||
      status == OfflinePackStatus.partial;

  bool get hasPendingOutbox => pendingOutboxCount > 0;

  String lastUpdatedLabel({required DateTime now}) {
    final updatedAt = lastUpdatedAt;
    if (updatedAt == null) return 'Last updated: never';
    final delta = now.difference(updatedAt.toUtc());
    if (delta.inMinutes < 1) return 'Last updated: just now';
    if (delta.inHours < 1) {
      return 'Last updated: ${delta.inMinutes}m ago';
    }
    if (delta.inDays < 1) {
      return 'Last updated: ${delta.inHours}h ago';
    }
    return 'Last updated: ${delta.inDays}d ago';
  }

  OfflinePackManifest copyWith({
    OfflinePackStatus? status,
    DateTime? lastUpdatedAt,
    OfflinePackRowCounts? rowCounts,
    List<OfflinePackScope>? missingScopes,
    List<String>? staleReasons,
    int? pendingOutboxCount,
    int? storageBytes,
    String? secureSnapshotRef,
    String? lastError,
    bool? evictionPinned,
    DateTime? lastAccessedAt,
  }) {
    return OfflinePackManifest(
      tripId: tripId,
      tier: tier,
      status: status ?? this.status,
      lastUpdatedAt: lastUpdatedAt ?? this.lastUpdatedAt,
      rowCounts: rowCounts ?? this.rowCounts,
      missingScopes: missingScopes ?? this.missingScopes,
      staleReasons: staleReasons ?? this.staleReasons,
      pendingOutboxCount: pendingOutboxCount ?? this.pendingOutboxCount,
      storageBytes: storageBytes ?? this.storageBytes,
      secureSnapshotRef: secureSnapshotRef ?? this.secureSnapshotRef,
      lastError: lastError ?? this.lastError,
      evictionPinned: evictionPinned ?? this.evictionPinned,
      lastAccessedAt: lastAccessedAt ?? this.lastAccessedAt,
    );
  }
}

class OfflinePackEvictionCandidate {
  const OfflinePackEvictionCandidate({
    required this.tripId,
    required this.tier,
    required this.status,
    required this.lastAccessedAt,
    this.tripEndDate,
    this.lifecycle = 'active',
    this.evictionPinned = false,
    this.pendingOutboxCount = 0,
    this.storageBytes = 0,
  });

  final String tripId;
  final OfflinePackTier tier;
  final OfflinePackStatus status;
  final DateTime? lastAccessedAt;
  final DateTime? tripEndDate;
  final String lifecycle;
  final bool evictionPinned;
  final int pendingOutboxCount;
  final int storageBytes;

  bool get hasPendingWrites => pendingOutboxCount > 0;
  bool get isProtected => evictionPinned || hasPendingWrites;

  bool isPastOrArchived(DateTime now) {
    final ended = tripEndDate != null && tripEndDate!.isBefore(now);
    return ended || lifecycle == 'archived' || lifecycle == 'closed';
  }
}

class OfflinePackEvictionPlan {
  const OfflinePackEvictionPlan({required this.evictTripIds});

  final List<String> evictTripIds;
}

class OfflinePackMapSnapshotPlan {
  const OfflinePackMapSnapshotPlan({
    required this.pinsOnly,
    required this.bulkTilePrefetch,
    required this.tileDownloadRequests,
    required this.licenseGuard,
  });

  final bool pinsOnly;
  final bool bulkTilePrefetch;
  final int tileDownloadRequests;
  final String licenseGuard;
}

int _intValue(Object? raw) {
  if (raw is int) return raw;
  if (raw is num) return raw.round();
  if (raw is String) return int.tryParse(raw) ?? 0;
  return 0;
}

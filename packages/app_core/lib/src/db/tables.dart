import 'package:drift/drift.dart';

/// Local mirror of `trips`. UI reads from here; remote sync lands in Slice 9.
class LocalTrips extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get destination => text().nullable()();
  TextColumn get startDate => text().nullable()();
  TextColumn get endDate => text().nullable()();
  TextColumn get ownerId => text()();
  TextColumn get baseCurrency => text()();
  TextColumn get lifecycle => text().withDefault(const Constant('active'))();
  TextColumn get budgetMode => text().withDefault(const Constant('none'))();
  IntColumn get budgetCents => integer().nullable()();
  DateTimeColumn get closeRequestedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Local mirror of `trip_members`.
class LocalTripMembers extends Table {
  TextColumn get tripId => text()();
  TextColumn get userId => text()();
  TextColumn get role => text()();
  TextColumn get status => text()();
  TextColumn get displayName => text().nullable()();
  DateTimeColumn get completedAt => dateTime().nullable()();
  DateTimeColumn get closeAcceptedAt => dateTime().nullable()();
  DateTimeColumn get closeObjectedAt => dateTime().nullable()();
  TextColumn get closeObjectionReason => text().nullable()();
  DateTimeColumn get closeNotifiedAt => dateTime().nullable()();
  DateTimeColumn get closeRemindedAt => dateTime().nullable()();
  DateTimeColumn get settleNudgedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {tripId, userId};
}

/// Local mirror of `expenses`.
class LocalExpenses extends Table {
  TextColumn get id => text()();
  TextColumn get tripId => text()();
  TextColumn get payerId => text()();
  IntColumn get amountCents => integer()();
  TextColumn get currency => text()();
  IntColumn get baseCents => integer()();
  RealColumn get fxRate => real()();
  TextColumn get description => text()();
  TextColumn get category => text().nullable()();
  DateTimeColumn get spentAt => dateTime()();
  TextColumn get createdBy => text()();
  DateTimeColumn get createdAt => dateTime()();
  TextColumn get receiptPath => text().nullable()();
  TextColumn get localReceiptPath => text().nullable()();
  RealColumn get capturedLat => real().nullable()();
  RealColumn get capturedLng => real().nullable()();
  DateTimeColumn get capturedAt => dateTime().nullable()();
  TextColumn get placeLabel => text().nullable()();
  TextColumn get placeId => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('committed'))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Local mirror of `places` (receipt/EXIF resolved locations).
class LocalPlaces extends Table {
  TextColumn get id => text()();
  TextColumn get tripId => text()();
  TextColumn get label => text()();
  TextColumn get address => text().nullable()();
  RealColumn get lat => real().nullable()();
  RealColumn get lng => real().nullable()();
  TextColumn get source => text()();
  RealColumn get confidence => real()();
  TextColumn get createdBy => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Local mirror of `expense_shares`.
class LocalExpenseShares extends Table {
  TextColumn get id => text()();
  TextColumn get expenseId => text()();
  TextColumn get userId => text()();
  IntColumn get shareCents => integer()();
  TextColumn get response => text().withDefault(const Constant('accepted'))();
  TextColumn get responseReason => text().nullable()();
  DateTimeColumn get respondedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Local mirror of `settlements` (mark / confirm; money moves outside Vamo).
class LocalSettlements extends Table {
  TextColumn get id => text()();
  TextColumn get tripId => text()();
  TextColumn get fromUser => text()();
  TextColumn get toUser => text()();
  IntColumn get amountCents => integer()();
  TextColumn get currency => text()();
  TextColumn get status => text()();
  TextColumn get method => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Slice 8 — solo capture notes.
class LocalTripNotes extends Table {
  TextColumn get id => text()();
  TextColumn get tripId => text()();
  TextColumn get title => text()();
  TextColumn get body => text()();
  DateTimeColumn get capturedAt => dateTime()();
  TextColumn get createdBy => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Slice 8 — solo capture photos (local file + optional remote storage path).
class LocalTripPhotos extends Table {
  TextColumn get id => text()();
  TextColumn get tripId => text()();
  TextColumn get localPath => text().nullable()();
  TextColumn get storagePath => text().nullable()();
  TextColumn get caption => text().nullable()();
  DateTimeColumn get capturedAt => dateTime()();
  TextColumn get createdBy => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// S18 — TripBoard plan items (mirrors trip_plan_items).
class LocalPlanItems extends Table {
  TextColumn get id => text()();
  TextColumn get tripId => text()();
  TextColumn get kind => text()();
  TextColumn get title => text()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get startsAt => dateTime().nullable()();
  DateTimeColumn get endsAt => dateTime().nullable()();
  TextColumn get externalRef => text().nullable()();
  TextColumn get attachmentPath => text().nullable()();
  IntColumn get position => integer().withDefault(const Constant(0))();
  TextColumn get createdBy => text()();
  TextColumn get updatedBy => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// S18 — shared checklist rows (mirrors trip_list_items).
class LocalTripListItems extends Table {
  TextColumn get id => text()();
  TextColumn get tripId => text()();
  TextColumn get listName => text()();
  TextColumn get label => text()();
  TextColumn get checkedBy => text().nullable()();
  DateTimeColumn get checkedAt => dateTime().nullable()();
  IntColumn get position => integer().withDefault(const Constant(0))();
  TextColumn get createdBy => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// S21 — event RSVP rows (mirrors trip_plan_item_rsvps).
class LocalPlanItemRsvps extends Table {
  TextColumn get id => text()();
  TextColumn get planItemId => text()();
  TextColumn get userId => text()();
  TextColumn get status => text()();
  DateTimeColumn get respondedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// S20 — per-trip constant FX rates (D4).
class LocalTripFxRates extends Table {
  TextColumn get id => text()();
  TextColumn get tripId => text()();
  TextColumn get currency => text()();
  RealColumn get rate => real()();
  TextColumn get source => text()();
  DateTimeColumn get capturedAt => dateTime()();
  TextColumn get capturedBy => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Slice 9 — queued remote writes (drained by SyncWorker).
class LocalSyncOutbox extends Table {
  TextColumn get id => text()();
  TextColumn get kind => text()();
  TextColumn get payload => text()();
  DateTimeColumn get createdAt => dateTime()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

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

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Local mirror of `expense_shares`.
class LocalExpenseShares extends Table {
  TextColumn get id => text()();
  TextColumn get expenseId => text()();
  TextColumn get userId => text()();
  IntColumn get shareCents => integer()();

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

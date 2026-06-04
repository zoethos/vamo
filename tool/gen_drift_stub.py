#!/usr/bin/env python3
"""Generates app_database.g.dart for the two-table Slice 1 schema.
Run: python tool/gen_drift_stub.py
Regenerate properly with: cd packages/app_core && dart run build_runner build
"""

from pathlib import Path

OUT = Path(__file__).resolve().parents[1] / "packages/app_core/lib/src/db/app_database.g.dart"

TRIPS_COLS = [
    ("id", "String", "DriftSqlType.string", True),
    ("name", "String", "DriftSqlType.string", True),
    ("destination", "String?", "DriftSqlType.string", False),
    ("startDate", "String?", "DriftSqlType.string", False),
    ("endDate", "String?", "DriftSqlType.string", False),
    ("ownerId", "String", "DriftSqlType.string", True),
    ("baseCurrency", "String", "DriftSqlType.string", True),
    ("createdAt", "DateTime", "DriftSqlType.dateTime", True),
    ("updatedAt", "DateTime", "DriftSqlType.dateTime", True),
]

MEMBERS_COLS = [
    ("tripId", "String", "DriftSqlType.string", True),
    ("userId", "String", "DriftSqlType.string", True),
    ("role", "String", "DriftSqlType.string", True),
    ("status", "String", "DriftSqlType.string", True),
    ("displayName", "String?", "DriftSqlType.string", False),
]

EXPENSES_COLS = [
    ("id", "String", "DriftSqlType.string", True),
    ("tripId", "String", "DriftSqlType.string", True),
    ("payerId", "String", "DriftSqlType.string", True),
    ("amountCents", "int", "DriftSqlType.int", True),
    ("currency", "String", "DriftSqlType.string", True),
    ("baseCents", "int", "DriftSqlType.int", True),
    ("fxRate", "double", "DriftSqlType.double", True),
    ("description", "String", "DriftSqlType.string", True),
    ("category", "String?", "DriftSqlType.string", False),
    ("spentAt", "DateTime", "DriftSqlType.dateTime", True),
    ("createdBy", "String", "DriftSqlType.string", True),
    ("createdAt", "DateTime", "DriftSqlType.dateTime", True),
]

SHARES_COLS = [
    ("id", "String", "DriftSqlType.string", True),
    ("expenseId", "String", "DriftSqlType.string", True),
    ("userId", "String", "DriftSqlType.string", True),
    ("shareCents", "int", "DriftSqlType.int", True),
]

SETTLEMENTS_COLS = [
    ("id", "String", "DriftSqlType.string", True),
    ("tripId", "String", "DriftSqlType.string", True),
    ("fromUser", "String", "DriftSqlType.string", True),
    ("toUser", "String", "DriftSqlType.string", True),
    ("amountCents", "int", "DriftSqlType.int", True),
    ("currency", "String", "DriftSqlType.string", True),
    ("status", "String", "DriftSqlType.string", True),
    ("method", "String?", "DriftSqlType.string", False),
    ("createdAt", "DateTime", "DriftSqlType.dateTime", True),
]

NOTES_COLS = [
    ("id", "String", "DriftSqlType.string", True),
    ("tripId", "String", "DriftSqlType.string", True),
    ("title", "String", "DriftSqlType.string", True),
    ("body", "String", "DriftSqlType.string", True),
    ("capturedAt", "DateTime", "DriftSqlType.dateTime", True),
    ("createdBy", "String", "DriftSqlType.string", True),
    ("createdAt", "DateTime", "DriftSqlType.dateTime", True),
]

OUTBOX_COLS = [
    ("id", "String", "DriftSqlType.string", True),
    ("kind", "String", "DriftSqlType.string", True),
    ("payload", "String", "DriftSqlType.string", True),
    ("createdAt", "DateTime", "DriftSqlType.dateTime", True),
    ("attempts", "int", "DriftSqlType.int", True),
    ("lastError", "String?", "DriftSqlType.string", False),
]

PHOTOS_COLS = [
    ("id", "String", "DriftSqlType.string", True),
    ("tripId", "String", "DriftSqlType.string", True),
    ("localPath", "String?", "DriftSqlType.string", False),
    ("storagePath", "String?", "DriftSqlType.string", False),
    ("caption", "String?", "DriftSqlType.string", False),
    ("capturedAt", "DateTime", "DriftSqlType.dateTime", True),
    ("createdBy", "String", "DriftSqlType.string", True),
    ("createdAt", "DateTime", "DriftSqlType.dateTime", True),
]


def snake(name: str) -> str:
    out = []
    for i, c in enumerate(name):
        if c.isupper() and i > 0:
            out.append("_")
        out.append(c.lower())
    return "".join(out)


def gen_table_class(table_dart: str, table_var: str, data_class: str, companion: str, cols, sql_name: str):
    col_defs = []
    col_list = []
    map_fields = []
    data_fields = []
    companion_fields = []
    companion_ctor = []
    companion_to_columns = []

    for name, dart_type, sql_type, required in cols:
        sql_col = snake(name)
        col_defs.append(
            f"  late final GeneratedColumn<{dart_type.replace('?', '')}> {name} = "
            f"GeneratedColumn<{dart_type.replace('?', '')}>("
            f"'{sql_col}', aliasedName, false,"
            f" type: {sql_type},"
            f"{' requiredDuringInsert: true,' if required and '?' not in dart_type else ''}"
            f"{' requiredDuringInsert: false,' if not required or '?' in dart_type else ''}"
            f");"
        )
        col_list.append(name)
        nullable = "?" in dart_type
        read = f"attachedDatabase.typeMapping.read({sql_type}, data['${{effectivePrefix}}{sql_col}'])"
        if nullable:
            map_fields.append(f"      {name}: {read},")
        else:
            map_fields.append(f"      {name}: {read}!,")
        data_fields.append(f"  final {dart_type} {name};")
        companion_fields.append(f"  final Value<{dart_type}> {name};")
        companion_ctor.append(f"    this.{name} = const Value.absent(),")
        companion_to_columns.append(
            f"    if ({name}.present) {{"
            f"\n      map['{sql_col}'] = Variable({name}.value);"
            f"\n    }}"
        )

    cols_joined = ", ".join(col_list)
    data_ctor = ",\n    ".join([f"required this.{c[0]}" if "?" not in c[1] else f"this.{c[0]}" for c in cols])
    data_ctor_params = ",\n    ".join(
        [f"required this.{c[0]}" if "?" not in c[1] else f"this.{c[0]}" for c in cols]
    )

    return f"""
class ${table_dart}Table extends {table_dart}
    with TableInfo<${table_dart}Table, {data_class}> {{
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  ${table_dart}Table(this.attachedDatabase, [this._alias]);
{chr(10).join(col_defs)}
  @override
  List<GeneratedColumn> get $columns => [{cols_joined}];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => '{sql_name}';
  @override
  {data_class} map(Map<String, dynamic> data, {{String? tablePrefix}}) {{
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return {data_class}(
{chr(10).join(map_fields)}
    );
  }}
}}

class {data_class} extends DataClass implements Insertable<{data_class}> {{
{chr(10).join(data_fields)}
  const {data_class}({{{data_ctor_params}}});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {{
    final map = <String, Expression>{{}};
{chr(10).join([f"    map['{snake(c[0])}'] = Variable({c[0]});" for c in cols])}
    return map;
  }}
  {companion} toCompanion(bool nullToAbsent) => {companion}(
{chr(10).join([f"    {c[0]}: Value({c[0]})," for c in cols])}
  );
}}

class {companion} extends UpdateCompanion<{data_class}> {{
{chr(10).join(companion_fields)}
  const {companion}({{
{chr(10).join(companion_ctor)}
  }});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {{
    final map = <String, Expression>{{}};
{chr(10).join(companion_to_columns)}
    return map;
  }}
}}
"""


header = """// GENERATED CODE — hand-stubbed; run `melos run build_runner` before analyze/test.
// dart format off

part of 'app_database.dart';

// ignore_for_file: type=lint
"""

trips = gen_table_class(
    "LocalTrips", "localTrips", "LocalTrip", "LocalTripsCompanion",
    TRIPS_COLS, "local_trips",
)
members = gen_table_class(
    "LocalTripMembers", "localTripMembers", "LocalTripMember", "LocalTripMembersCompanion",
    MEMBERS_COLS, "local_trip_members",
)
expenses = gen_table_class(
    "LocalExpenses", "localExpenses", "LocalExpense", "LocalExpensesCompanion",
    EXPENSES_COLS, "local_expenses",
)
shares = gen_table_class(
    "LocalExpenseShares", "localExpenseShares", "LocalExpenseShare", "LocalExpenseSharesCompanion",
    SHARES_COLS, "local_expense_shares",
)
settlements = gen_table_class(
    "LocalSettlements", "localSettlements", "LocalSettlement", "LocalSettlementsCompanion",
    SETTLEMENTS_COLS, "local_settlements",
)
notes = gen_table_class(
    "LocalTripNotes", "localTripNotes", "LocalTripNote", "LocalTripNotesCompanion",
    NOTES_COLS, "local_trip_notes",
)
photos = gen_table_class(
    "LocalTripPhotos", "localTripPhotos", "LocalTripPhoto", "LocalTripPhotosCompanion",
    PHOTOS_COLS, "local_trip_photos",
)
outbox = gen_table_class(
    "LocalSyncOutbox", "localSyncOutbox", "LocalSyncOutboxData", "LocalSyncOutboxCompanion",
    OUTBOX_COLS, "local_sync_outbox",
)

footer = """
abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  late final $LocalTripsTable localTrips = $LocalTripsTable(this);
  late final $LocalTripMembersTable localTripMembers = $LocalTripMembersTable(this);
  late final $LocalExpensesTable localExpenses = $LocalExpensesTable(this);
  late final $LocalExpenseSharesTable localExpenseShares = $LocalExpenseSharesTable(this);
  late final $LocalSettlementsTable localSettlements = $LocalSettlementsTable(this);
  late final $LocalTripNotesTable localTripNotes = $LocalTripNotesTable(this);
  late final $LocalTripPhotosTable localTripPhotos = $LocalTripPhotosTable(this);
  late final $LocalSyncOutboxTable localSyncOutbox = $LocalSyncOutboxTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities =>
      [localTrips, localTripMembers, localExpenses, localExpenseShares, localSettlements, localTripNotes, localTripPhotos, localSyncOutbox];
}
"""

OUT.write_text(header + trips + members + expenses + shares + settlements + notes + photos + outbox + footer, encoding="utf-8")
print(f"Wrote {OUT}")

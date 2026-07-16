import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, it } from "node:test";

import {
  resetDisposableTestDatabase,
  resolveDisposableTestDatabaseUrl
} from "./disposable-test-database.js";

describe("resolveDisposableTestDatabaseUrl", () => {
  it("allows local disposable Postgres without remote confirmation", () => {
    assert.equal(
      resolveDisposableTestDatabaseUrl("postgresql://postgres:password@127.0.0.1:55433/ingestion_test"),
      "postgresql://postgres:password@127.0.0.1:55433/ingestion_test"
    );
  });

  it("requires confirmation and allowlisting when localhost uses another port", () => {
    assert.throws(
      () => resolveDisposableTestDatabaseUrl("postgresql://postgres:password@localhost:5432/ingestion_test"),
      /INGESTION_TEST_DATABASE_URL is refused/
    );

    assert.equal(
      resolveDisposableTestDatabaseUrl("postgresql://postgres:password@localhost:5432/ingestion_test", {
        CONFIRM_DISPOSABLE_TEST_DB: "YES",
        INGESTION_TEST_DATABASE_HOST_ALLOWLIST: "localhost"
      }),
      "postgresql://postgres:password@localhost:5432/ingestion_test"
    );
  });

  it("refuses a remote database without both explicit safeguards", () => {
    assert.throws(
      () =>
        resolveDisposableTestDatabaseUrl("postgresql://postgres:password@db.example.test:5432/postgres"),
      /INGESTION_TEST_DATABASE_URL is refused/
    );

    assert.throws(
      () =>
        resolveDisposableTestDatabaseUrl(
          "postgresql://postgres:password@db.example.test:5432/postgres",
          { CONFIRM_DISPOSABLE_TEST_DB: "YES" }
        ),
      /INGESTION_TEST_DATABASE_URL is refused/
    );
  });

  it("allows an explicitly confirmed remote disposable host", () => {
    const url = "postgresql://postgres:password@db.ingestion-test.example:5432/postgres";
    assert.equal(
      resolveDisposableTestDatabaseUrl(url, {
        CONFIRM_DISPOSABLE_TEST_DB: "YES",
        INGESTION_TEST_DATABASE_HOST_ALLOWLIST: "db.ingestion-test.example"
      }),
      url
    );
  });

  it("refuses a test URL that matches any configured live database", () => {
    const url = "postgresql://postgres:password@db.control.example:5432/postgres";
    assert.throws(
      () =>
        resolveDisposableTestDatabaseUrl(url, {
          CONFIRM_DISPOSABLE_TEST_DB: "YES",
          INGESTION_TEST_DATABASE_HOST_ALLOWLIST: "db.control.example",
          INGESTION_CONTROL_OWNER_DATABASE_URL: url
        }),
      /matches a configured live control or Vamo database URL/
    );
  });

  it("refuses malformed and non-Postgres connection strings", () => {
    assert.throws(
      () => resolveDisposableTestDatabaseUrl("https://db.example.test"),
      /valid PostgreSQL connection string/
    );
  });

  it("runs destructive reset SQL only after the URL guard passes", async () => {
    const queries: string[] = [];
    await resetDisposableTestDatabase(
      { query: async (sql) => void queries.push(sql) },
      "postgresql://postgres:password@localhost:55433/ingestion_test",
      {
        schemas: ["ingestion_platform"],
        roles: ["confluendo_app"],
        ownedRoles: ["confluendo_app"],
        tables: [{ schema: "public", name: "location_canonicals" }],
        functions: [{ schema: "public", name: "promote_location_aliases", arguments: "integer" }]
      }
    );

    assert.equal(queries.length, 5);
    assert.match(queries[0]!, /drop schema if exists "ingestion_platform" cascade/);
    assert.match(queries[1]!, /drop function if exists "public"\."promote_location_aliases"\(integer\) cascade/);
    assert.match(queries[2]!, /drop table if exists "public"\."location_canonicals" cascade/);
    assert.match(queries[3]!, /drop owned by "confluendo_app"/);
    assert.match(queries[4]!, /drop role if exists "confluendo_app"/);
  });

  it("keeps destructive setup SQL inside the guarded reset helper", () => {
    const rawDestructiveSql = /\b(?:drop\s+(?:schema|role|owned|table|function)|truncate|delete\s+from)\b/i;
    const sourceFiles = [
      ...listTypeScriptFiles("core/test"),
      ...listTypeScriptFiles("adapters/target/test")
    ].filter(
      (file) =>
        !file.endsWith("disposable-test-database.ts") &&
        !file.endsWith("disposable-test-database.test.ts")
    );

    for (const file of sourceFiles) {
      assert.doesNotMatch(readFileSync(file, "utf8"), rawDestructiveSql, file);
    }
  });
});

function listTypeScriptFiles(directory: string): string[] {
  return readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) return listTypeScriptFiles(path);
    return entry.name.endsWith(".ts") ? [path] : [];
  });
}

import assert from "node:assert/strict";
import { describe, it } from "node:test";

import {
  assertConfluendoControlRuntimeDatabaseUrl,
  deriveConfluendoControlRuntimeDatabaseUrl
} from "../src/control-runtime-database-role.js";

describe("Confluendo control runtime database role", () => {
  it("accepts only the least-privilege runtime role", () => {
    assert.doesNotThrow(() =>
      assertConfluendoControlRuntimeDatabaseUrl(
        "postgresql://confluendo_app.leqlomnszaboypinjroc:secret@aws-0-eu-central-1.pooler.supabase.com:5432/postgres"
      )
    );
    assert.throws(
      () =>
        assertConfluendoControlRuntimeDatabaseUrl(
          "postgresql://postgres:secret@db.leqlomnszaboypinjroc.supabase.co:5432/postgres"
        ),
      /confluendo_app runtime role/
    );
    assert.throws(
      () =>
        assertConfluendoControlRuntimeDatabaseUrl(
          "postgresql://postgres.leqlomnszaboypinjroc:secret@aws-0-eu-central-1.pooler.supabase.com:5432/postgres"
        ),
      /confluendo_app runtime role/
    );
  });

  it("derives the session-pooler runtime URL without changing its endpoint", () => {
    const runtimeUrl = deriveConfluendoControlRuntimeDatabaseUrl(
      "postgresql://postgres.leqlomnszaboypinjroc:owner-secret@aws-0-eu-central-1.pooler.supabase.com:5432/postgres?sslmode=require",
      "rotated runtime secret"
    );
    const parsed = new URL(runtimeUrl);

    assert.equal(parsed.username, "confluendo_app.leqlomnszaboypinjroc");
    assert.equal(parsed.hostname, "aws-0-eu-central-1.pooler.supabase.com");
    assert.equal(parsed.port, "5432");
    assert.equal(parsed.pathname, "/postgres");
    assert.equal(parsed.searchParams.get("sslmode"), "require");
  });

  it("refuses an owner URL without an identifiable Supabase project reference", () => {
    assert.throws(
      () =>
        deriveConfluendoControlRuntimeDatabaseUrl(
          "postgresql://postgres:owner-secret@pooler.example.test:5432/postgres",
          "runtime-secret"
        ),
      /Could not derive the Supabase project reference/
    );
  });
});

import { assertStringIncludes } from "jsr:@std/assert@1.0.19";

const migrationUrl = new URL(
  "../../migrations/20260811130000_custom_expense_split.sql",
  import.meta.url,
);

Deno.test("custom split RPC preserves and validates explicit member shares", async () => {
  const migration = await Deno.readTextFile(migrationUrl);

  assertStringIncludes(
    migration,
    "v_share_cents := (v_share->>'share_cents')::bigint",
  );
  assertStringIncludes(migration, "share_cents must not be negative");
  assertStringIncludes(migration, "duplicate share user");
  assertStringIncludes(
    migration,
    "shares must include each active member exactly once",
  );
  assertStringIncludes(migration, "sum(shares)=% must equal base_cents=%");
  assertStringIncludes(
    migration,
    "values (v_share_id, p_id, v_share_user, v_share_cents, 'accepted'::share_response)",
  );
});

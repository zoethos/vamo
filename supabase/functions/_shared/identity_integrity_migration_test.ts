import { assertEquals, assertStringIncludes } from "jsr:@std/assert@1.0.19";

const migrationUrl = new URL(
  "../../migrations/20260811120000_identity_integrity_signal.sql",
  import.meta.url,
);
const lifecycleJobUrl = new URL(
  "../trip-lifecycle-jobs/index.ts",
  import.meta.url,
);

Deno.test("identity integrity signal is aggregate-only and service-owned", async () => {
  const migration = await Deno.readTextFile(migrationUrl);
  const lifecycleJob = await Deno.readTextFile(lifecycleJobUrl);

  assertStringIncludes(migration, "identity_integrity_summary");
  assertStringIncludes(migration, "email_confirmed_at is not null");
  assertStringIncludes(migration, "auth.identities");
  assertStringIncludes(migration, "privaterelay.appleid.com");
  assertStringIncludes(
    migration,
    "revoke all on function public.identity_integrity_summary() from public",
  );
  assertStringIncludes(
    migration,
    "grant execute on function public.identity_integrity_summary() to service_role",
  );
  assertEquals(migration.includes("array_agg"), false);
  assertStringIncludes(
    lifecycleJob,
    'supabase.rpc("identity_integrity_summary")',
  );
  assertStringIncludes(
    lifecycleJob,
    "identity_integrity: identityIntegrityError",
  );
});

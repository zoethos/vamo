import { assertEquals, assertStringIncludes } from "jsr:@std/assert@1.0.19";

const migrationUrl = new URL(
  "../../migrations/20260810120000_municipality_place_baseline.sql",
  import.meta.url,
);

Deno.test("municipality baseline keeps product writes in declared inbox items", async () => {
  const migration = await Deno.readTextFile(migrationUrl);

  assertStringIncludes(
    migration,
    "create or replace function confluendo_inbox.apply_confluendo_shipment",
  );
  assertStringIncludes(
    migration,
    "when v_item.payload ? 'administrative_parent_code'",
  );
  assertStringIncludes(migration, "when v_item.payload ? 'dataset_version'");
  assertStringIncludes(migration, "when v_item.payload ? 'valid_from'");
  assertStringIncludes(migration, "when v_item.payload ? 'valid_to'");
  assertEquals(migration.includes("create trigger "), false);
  assertEquals(
    migration.includes("insert into public.location_aliases"),
    false,
  );
});

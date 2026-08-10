import { assertEquals, assertStringIncludes } from "jsr:@std/assert@1.0.19";

const migrationUrl = new URL(
  "../../migrations/20260810130000_location_canonicals_spatial_index.sql",
  import.meta.url,
);

Deno.test("location canonical spatial migration is additive and indexed", async () => {
  const migration = await Deno.readTextFile(migrationUrl);

  assertStringIncludes(
    migration,
    "create extension if not exists postgis with schema extensions",
  );
  assertStringIncludes(
    migration,
    "create extension if not exists pg_trgm with schema extensions",
  );
  assertStringIncludes(
    migration,
    "location_canonicals_coordinate_pair_check",
  );
  assertStringIncludes(
    migration,
    "location_canonicals_municipality_coordinates_required",
  );
  assertStringIncludes(migration, "extensions.geography(point, 4326)");
  assertStringIncludes(migration, "generated always as");
  assertStringIncludes(migration, "extensions.st_makepoint(longitude, latitude)");
  assertStringIncludes(migration, "using gist (geom)");
  assertStringIncludes(migration, "extensions.gin_trgm_ops");
  assertStringIncludes(
    migration,
    "(country_code, feature_type, name_norm)",
  );
  assertEquals(
    migration.includes("rename to locations_core"),
    false,
    "The proven location_canonicals contract must remain stable.",
  );
  assertEquals(
    migration.includes("rename to location_source_ids"),
    false,
    "The proven location_source_refs contract must remain stable.",
  );
});

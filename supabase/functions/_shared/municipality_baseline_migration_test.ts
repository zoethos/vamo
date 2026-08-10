import { assertEquals, assertStringIncludes } from "jsr:@std/assert@1.0.19";

const municipalityMigrationName =
  "20260810120000_municipality_place_baseline.sql";
const migrationUrl = new URL(
  `../../migrations/${municipalityMigrationName}`,
  import.meta.url,
);
const consumerSnapshotManifestUrl = new URL(
  "../../confluendo-consumer-migration-snapshots.json",
  import.meta.url,
);

interface ConsumerMigrationSnapshotManifest {
  version: number;
  consumer: string;
  migrations: Array<{
    sourceMigration: string;
    consumerMigration: string;
    sha256: string;
  }>;
}

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

Deno.test("municipality baseline remains aligned with the recorded Confluendo consumer snapshot", async () => {
  const manifest = JSON.parse(
    await Deno.readTextFile(consumerSnapshotManifestUrl),
  ) as ConsumerMigrationSnapshotManifest;
  const snapshot = manifest.migrations.find(
    (entry) => entry.sourceMigration === municipalityMigrationName,
  );

  assertEquals(manifest.version, 1);
  assertEquals(manifest.consumer, "confluendo");
  assertEquals(
    snapshot?.consumerMigration,
    "examples/consumers/vamo-place-intelligence/migrations/20260810120000_municipality_place_baseline.sql",
  );
  assertEquals(snapshot?.sha256.match(/^[a-f0-9]{64}$/)?.[0], snapshot?.sha256);

  const digest = await crypto.subtle.digest(
    "SHA-256",
    await Deno.readFile(migrationUrl),
  );
  const actualSha256 = Array.from(
    new Uint8Array(digest),
    (byte) => byte.toString(16).padStart(2, "0"),
  ).join("");

  assertEquals(
    actualSha256,
    snapshot?.sha256,
    "The Vamo municipality migration changed. Re-import its exact bytes into Confluendo and update supabase/confluendo-consumer-migration-snapshots.json in the same cross-repository change.",
  );
});

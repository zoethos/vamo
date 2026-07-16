import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, it } from "node:test";

import type { FsqPortalPlaceRecord } from "../../adapters/source/src/fsq-os-places-portal-iceberg-acquire.js";
import {
  FSQ_SNAPSHOT_ACQUIRE_CONFIRMATION_ENV,
  FSQ_SNAPSHOT_ACQUIRE_CONFIRMATION_VALUE,
  formatFsqSnapshotAcquireLog,
  redactFsqSnapshotAcquireLogValue,
  runFsqSnapshotAcquire
} from "../src/fsq-snapshot-acquire.js";
import { SNAPSHOT_ARTIFACT_BUNDLE_FILES } from "../src/snapshot-artifact-store.js";

const testDir = dirname(fileURLToPath(import.meta.url));
const packageRoot = join(testDir, "..", "..", "..");
const acquireModulePath = join(packageRoot, "core/src/fsq-snapshot-acquire.ts");
const adapterModulePath = join(
  packageRoot,
  "adapters/source/src/fsq-os-places-portal-iceberg-acquire.ts"
);
const acquireScriptPath = join(packageRoot, "scripts/run-ip18-fsq-snapshot-acquire.mjs");

const fixtureRecords: FsqPortalPlaceRecord[] = [
  {
    fsqPlaceId: "rome_colosseum",
    name: "Colosseum",
    latitude: 41.8902,
    longitude: 12.4922,
    geography: "rome-italy",
    category: "landmark"
  },
  {
    fsqPlaceId: "paris_louvre",
    name: "Louvre Museum",
    latitude: 48.8606,
    longitude: 2.3376,
    geography: "paris-france",
    category: "poi"
  }
];

describe("runFsqSnapshotAcquire", () => {
  it("preview mode is write-free and token-free", async () => {
    const result = await runFsqSnapshotAcquire({
      countries: ["italy"],
      categories: ["poi"],
      preview: true
    });
    assert.equal(result.ok, true);
    if (result.ok) {
      assert.equal(result.result.mode, "preview");
      assert.equal(result.result.plan.scopes.length, 1);
    }
  });

  it("execute mode rejects missing confirmation and portal access token", async () => {
    const missingConfirmation = await runFsqSnapshotAcquire({
      countries: ["italy"],
      categories: ["poi"],
      preview: false,
      portalAccessToken: "secret-portal-token-123"
    });
    assert.deepEqual(missingConfirmation, { ok: false, blocks: ["confirmation_missing"] });

    const missingPortalToken = await runFsqSnapshotAcquire({
      countries: ["italy"],
      categories: ["poi"],
      preview: false,
      confirmation: FSQ_SNAPSHOT_ACQUIRE_CONFIRMATION_VALUE
    });
    assert.deepEqual(missingPortalToken, { ok: false, blocks: ["portal_access_token_missing"] });
  });

  it("rejects out-of-bounds country and category scopes", async () => {
    const result = await runFsqSnapshotAcquire({
      countries: ["atlantis"],
      categories: ["spaceship"],
      preview: true
    });
    assert.equal(result.ok, false);
    if (!result.ok) {
      assert.ok(result.blocks.includes("country_out_of_bounds:atlantis"));
      assert.ok(result.blocks.includes("category_out_of_bounds:spaceship"));
    }
  });

  it("stores immutable checksum-verified artifacts on execute without live provider calls", async () => {
    const artifactStoreBaseDir = mkdtempSync(join(tmpdir(), "fsq-acquire-artifacts-"));
    try {
      const result = await runFsqSnapshotAcquire({
        countries: ["italy", "france"],
        categories: ["poi", "landmark"],
        preview: false,
        confirmation: FSQ_SNAPSHOT_ACQUIRE_CONFIRMATION_VALUE,
        portalAccessToken: "super-secret-portal-token",
        fixtureRecords,
        artifactStoreBaseDir,
        acquiredAt: "2026-07-01T12:00:00.000Z",
        now: "2026-07-01T12:00:00.000Z"
      });

      assert.equal(result.ok, true);
      if (!result.ok || result.result.mode !== "execute" || !result.result.accepted) {
        return;
      }

      assert.match(result.result.releaseId, /^fsq_os_places-/);
      assert.match(result.result.artifactKey, /^fsq-os-places-snapshot\//);
      assert.equal(result.result.coverage.validRowCount, 2);
      for (const fileName of SNAPSHOT_ARTIFACT_BUNDLE_FILES) {
        assert.ok(
          readFileSync(
            join(artifactStoreBaseDir, ...result.result.artifactKey.split("/"), fileName),
            "utf8"
          ).length > 0
        );
      }

      const log = formatFsqSnapshotAcquireLog(result, "super-secret-portal-token");
      assert.doesNotMatch(log, /super-secret-portal-token/);
      assert.doesNotMatch(log, /FSQ_OS_PLACES_PORTAL_ACCESS_TOKEN/);
    } finally {
      rmSync(artifactStoreBaseDir, { recursive: true, force: true });
    }
  });

  it("redacts portal access tokens from formatted logs", () => {
    const redacted = redactFsqSnapshotAcquireLogValue(
      "authorization Bearer secret-portal-token",
      "secret-portal-token"
    );
    assert.equal(redacted, "authorization Bearer [REDACTED_PORTAL_ACCESS_TOKEN]");
  });
});

describe("fsq snapshot acquisition artifact", () => {
  it("keeps provider access only in the dedicated Portal/Iceberg adapter", () => {
    const acquireSource = readFileSync(acquireModulePath, "utf8");
    const scriptSource = readFileSync(acquireScriptPath, "utf8");
    const combined = `${acquireSource}\n${scriptSource}`;

    assert.doesNotMatch(combined, /\bfetch\s*\(/);
    assert.doesNotMatch(combined, /catalog\.foursquare\.com/);
    assert.doesNotMatch(combined, /@duckdb\/node-api/);
  });

  it("requires explicit execute confirmation in the CLI", () => {
    const scriptSource = readFileSync(acquireScriptPath, "utf8");
    assert.match(scriptSource, /CONFIRM_CONFLUENDO_FSQ_SNAPSHOT_ACQUIRE/);
    assert.match(scriptSource, /Preview plan/);
    assert.match(scriptSource, /--artifact-store-dir/);
    assert.match(scriptSource, /FSQ_OS_PLACES_PORTAL_ACCESS_TOKEN/);
  });

  it("does not expose activation or queue reseed paths in acquisition modules", () => {
    const adapterSource = readFileSync(adapterModulePath, "utf8");

    assert.doesNotMatch(adapterSource, /applySnapshotSupplyToQueueSnapshot/);
    assert.doesNotMatch(adapterSource, /persistBatchQueueSnapshot/);
    assert.doesNotMatch(adapterSource, /batch-queue-seed/i);
    assert.doesNotMatch(adapterSource, /register_snapshot_release/);
  });

  it("documents the confirmation env constant without embedding token values", () => {
    assert.equal(FSQ_SNAPSHOT_ACQUIRE_CONFIRMATION_ENV, "CONFIRM_CONFLUENDO_FSQ_SNAPSHOT_ACQUIRE");
    assert.equal(FSQ_SNAPSHOT_ACQUIRE_CONFIRMATION_VALUE, "YES");
  });
});

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";
import { Client } from "pg";

import { registerSnapshotRelease } from "../src/snapshot-release-registry-control.js";
import type { SourceAcquisitionReleaseRecord } from "../src/source-acquisition-contract.js";

const controlSchemaSql = readFileSync("core/sql/control_schema.sql", "utf8");
const confluendoBootstrapSql = readFileSync(
  "core/sql/control_bootstrap_confluendo.sql",
  "utf8"
);
import {
  resetDisposableTestDatabase,
  resolveDisposableTestDatabaseUrl
} from "./disposable-test-database.js";

const databaseUrl = resolveDisposableTestDatabaseUrl(process.env.INGESTION_TEST_DATABASE_URL);

function sampleRelease(overrides: Partial<SourceAcquisitionReleaseRecord> = {}): SourceAcquisitionReleaseRecord {
  return {
    kind: "ingestion.source_acquisition_release",
    releaseId: "fsq_os_places-20260701-deadbeefcafe",
    sourceKey: "fsq-os-places-snapshot",
    sourceProvider: "fsq_os_places",
    acquiredAt: "2026-07-01T12:00:00.000Z",
    provenanceUrl: "https://places.foursquare.com/products/open-source-places",
    inputSha256: "a".repeat(64),
    outputSha256: "b".repeat(64),
    sourceAttribution: "FSQ Open Source Places",
    licenseIdentifier: "FSQ-OS-Places",
    retentionStatement: "Retain until superseded.",
    intendedConsumer: "vamo",
    intendedTarget: "vamo-place-intelligence",
    artifactKey: "fsq-os-places-snapshot/fsq_os_places-20260701-deadbeefcafe/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    artifactUri: "file:///tmp/confluendo-snapshot-artifacts/fsq-os-places-snapshot",
    status: "activation_ready",
    coverage: {
      kind: "ingestion.snapshot_coverage_report",
      releaseId: "fsq_os_places-20260701-deadbeefcafe",
      derivedFromValidRowsOnly: true,
      validRowCount: 2,
      invalidRowCount: 0,
      duplicateRowCount: 0,
      outOfScopeRowCount: 0,
      byCountry: { italy: 1, france: 1 },
      byPoiType: { poi: 1, landmark: 1 }
    },
    rowCounts: {
      valid: 2,
      invalid: 0,
      duplicate: 0,
      outOfScope: 0
    },
    ...overrides
  };
}

describe("snapshot release registry control", () => {
  it("declares registry table and owner-controlled registration function", () => {
    assert.match(controlSchemaSql, /ingestion_snapshot_releases/);
    assert.match(controlSchemaSql, /create or replace function ingestion_platform\.register_snapshot_release/);
    assert.match(controlSchemaSql, /revoke all on function ingestion_platform\.register_snapshot_release/);
    assert.match(confluendoBootstrapSql, /grant select on ingestion_platform\.ingestion_snapshot_releases to confluendo_app/i);
    assert.match(
      confluendoBootstrapSql,
      /grant execute on function ingestion_platform\.register_snapshot_release/i
    );
    assert.doesNotMatch(
      confluendoBootstrapSql,
      /grant update on ingestion_platform\.ingestion_snapshot_releases/i
    );
  });

  it(
    "registers validated releases atomically with audit and forbids direct app updates",
    { skip: databaseUrl ? false : "Set INGESTION_TEST_DATABASE_URL for DB smoke." },
    async () => {
      assert.ok(databaseUrl);
      const owner = new Client({ connectionString: databaseUrl });
      await owner.connect();

      try {
        await resetDisposableTestDatabase(owner, databaseUrl!, { schemas: ["ingestion_platform"] });
        await resetDisposableTestDatabase(owner, databaseUrl!, { roles: ["confluendo_app"] });
        await owner.query(controlSchemaSql);
        await owner.query("create role confluendo_app login password 'test'");
        await owner.query(confluendoBootstrapSql);

        const registered = await registerSnapshotRelease({
          client: owner,
          projectKey: "vamo",
          release: sampleRelease(),
          actor: { type: "operator", id: "dba@example.com" },
          auditReason: "Register validated FSQ snapshot release after acquisition execute."
        });

        assert.equal(registered.status, "activation_ready");
        assert.equal(registered.releaseId, "fsq_os_places-20260701-deadbeefcafe");
        assert.ok(registered.auditId);

        const releaseRow = await owner.query<{ status: string; artifact_key: string }>(
          `
            select status, artifact_key
            from ingestion_platform.ingestion_snapshot_releases
            where release_id = $1
          `,
          ["fsq_os_places-20260701-deadbeefcafe"]
        );
        assert.equal(releaseRow.rows[0]?.status, "activation_ready");
        assert.match(releaseRow.rows[0]?.artifact_key ?? "", /^fsq-os-places-snapshot\//);

        const auditRow = await owner.query<{ action: string; reason: string }>(
          `
            select action, reason
            from ingestion_platform.ingestion_audit_log
            where id = $1
          `,
          [registered.auditId]
        );
        assert.equal(auditRow.rows[0]?.action, "register_snapshot_release");
        assert.match(auditRow.rows[0]?.reason ?? "", /validated FSQ snapshot release/);

        const app = new Client({
          connectionString: databaseUrl.replace(/\/\/[^@]+@/, "//confluendo_app:test@")
        });
        await app.connect();
        try {
          await assert.rejects(
            () =>
              app.query(
                `
                  update ingestion_platform.ingestion_snapshot_releases
                  set status = 'superseded'
                  where release_id = 'fsq_os_places-20260701-deadbeefcafe'
                `
              ),
            /permission denied/i
          );

          const appRegistered = await registerSnapshotRelease({
            client: app,
            projectKey: "vamo",
            release: sampleRelease({
              releaseId: "fsq_os_places-20260701-cafebabef00d",
              outputSha256: "c".repeat(64),
              artifactKey:
                "fsq-os-places-snapshot/fsq_os_places-20260701-cafebabef00d/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
            }),
            actor: { type: "operator", id: "operator@example.com" },
            auditReason: "Second validated release registration smoke."
          });
          assert.equal(appRegistered.status, "activation_ready");
        } finally {
          await app.end();
        }
      } finally {
        await resetDisposableTestDatabase(owner, databaseUrl!, { schemas: ["ingestion_platform"] });
        await resetDisposableTestDatabase(owner, databaseUrl!, { roles: ["confluendo_app"] });
        await owner.end();
      }
    }
  );
});

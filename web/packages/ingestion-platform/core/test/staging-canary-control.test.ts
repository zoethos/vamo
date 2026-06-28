import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { after, before, beforeEach, describe, it } from "node:test";
import { Client } from "pg";

import { recordStagingCanaryApproval } from "../src/staging-canary-control.js";

const databaseUrl = process.env.INGESTION_TEST_DATABASE_URL;
const schemaSql = readFileSync("core/sql/control_schema.sql", "utf8");

describe(
  "staging canary approval recorder",
  { skip: databaseUrl ? false : "Set INGESTION_TEST_DATABASE_URL for staging-canary control smoke." },
  () => {
    let client: Client;

    before(async () => {
      assert.ok(databaseUrl);
      client = new Client({ connectionString: databaseUrl });
      await client.connect();
    });

    after(async () => {
      await client.query("drop schema if exists ingestion_platform cascade");
      await client.end();
    });

    beforeEach(async () => {
      await client.query("drop schema if exists ingestion_platform cascade");
      await client.query(schemaSql);
      await client.query(
        `insert into ingestion_platform.ingestion_projects (project_key, display_name)
         values ('vamo', 'Vamo')`
      );
    });

    it("records an accepted approval with reason and payload", async () => {
      const result = await recordStagingCanaryApproval({
        client,
        projectKey: "vamo",
        targetId: "vamo-place-intelligence-staging",
        accepted: true,
        actor: { type: "operator", id: "supabase:user-1" },
        reason: "first Rome landmark canary",
        payload: { write: { writeCount: 3 }, environment: "staging" }
      });
      assert.equal(result.ok, true);
      assert.ok(result.auditId);

      const row = await client.query<{
        action: string;
        reason: string;
        target_id: string;
        accepted: boolean;
        write_count: number;
      }>(
        `select action,
                reason,
                target_id,
                (payload->>'accepted')::boolean as accepted,
                (payload#>>'{write,writeCount}')::int as write_count
         from ingestion_platform.ingestion_audit_log
         order by id desc
         limit 1`
      );
      assert.equal(row.rows[0]?.action, "approve_staging_canary");
      assert.equal(row.rows[0]?.reason, "first Rome landmark canary");
      assert.equal(row.rows[0]?.target_id, "vamo-place-intelligence-staging");
      assert.equal(row.rows[0]?.accepted, true);
      assert.equal(row.rows[0]?.write_count, 3);
    });

    it("records a rejected approval under a distinct action", async () => {
      const result = await recordStagingCanaryApproval({
        client,
        projectKey: "vamo",
        targetId: "vamo-place-intelligence-staging",
        accepted: false,
        actor: { type: "operator", id: "supabase:user-1" },
        reason: "attempted promotion without fresh step-up",
        payload: { blocks: ["fresh_step_up_required"] }
      });
      assert.equal(result.ok, true);

      const row = await client.query<{ action: string; accepted: boolean }>(
        `select action, (payload->>'accepted')::boolean as accepted
         from ingestion_platform.ingestion_audit_log
         order by id desc
         limit 1`
      );
      assert.equal(row.rows[0]?.action, "reject_staging_canary");
      assert.equal(row.rows[0]?.accepted, false);
    });

    it("throws when the project key is unknown", async () => {
      await assert.rejects(
        recordStagingCanaryApproval({
          client,
          projectKey: "missing-project",
          targetId: "x",
          accepted: true,
          actor: { type: "operator", id: "supabase:user-1" },
          reason: "x",
          payload: {}
        }),
        /project was not found/
      );
    });
  }
);

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { after, before, beforeEach, describe, it } from "node:test";
import { Client } from "pg";

import {
  recordStagingCanaryApproval,
  recordStagingCanaryShipment
} from "../src/staging-canary-control.js";

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

    it("records a staging canary shipment ledger tied to an approval audit id", async () => {
      const approval = await recordStagingCanaryApproval({
        client,
        projectKey: "vamo",
        targetId: "vamo-place-intelligence-staging",
        accepted: true,
        actor: { type: "operator", id: "supabase:user-1" },
        reason: "first Rome landmark canary",
        payload: { plan: { write: { writeCount: 1 }, environment: "staging" } }
      });
      assert.ok(approval.auditId);

      const shipment = await recordStagingCanaryShipment({
        client,
        projectKey: "vamo",
        targetId: "vamo-place-intelligence-staging",
        targetAdapter: "postgres",
        approvalAuditId: approval.auditId,
        actor: { type: "operator", id: "supabase:user-1" },
        reason: "first Rome landmark canary",
        counts: { insert: 1, update: 0, noOp: 1, writeCount: 1 },
        items: [
          {
            targetTable: "location_canonicals",
            operation: "insert",
            recordKey: "fsq:rome:colosseum",
            idempotencyKey: "location_canonicals:fsq:rome:colosseum",
            keys: { canonical_key: "fsq:rome:colosseum" },
            columns: ["canonical_key", "display_name"],
            priorState: null
          },
          {
            targetTable: "location_canonicals",
            operation: "no_op",
            recordKey: "fsq:rome:pantheon",
            idempotencyKey: "location_canonicals:fsq:rome:pantheon",
            keys: { canonical_key: "fsq:rome:pantheon" },
            columns: ["canonical_key", "display_name"],
            priorState: null
          }
        ]
      });

      assert.equal(shipment.ok, true);
      assert.ok(shipment.shipmentId);
      assert.ok(shipment.auditId);

      const row = await client.query<{
        mode: string;
        status: string;
        approval_audit_id: string;
        item_count: string;
        applied_count: string;
        skipped_count: string;
      }>(
        `
          select s.mode,
                 s.status,
                 s.summary->>'approvalAuditId' as approval_audit_id,
                 count(i.id)::text as item_count,
                 count(i.id) filter (where i.status = 'applied')::text as applied_count,
                 count(i.id) filter (where i.status = 'skipped')::text as skipped_count
          from ingestion_platform.ingestion_shipments s
          join ingestion_platform.ingestion_shipment_items i on i.shipment_id = s.id
          where s.id = $1::bigint
          group by s.id
        `,
        [shipment.shipmentId]
      );
      assert.equal(row.rows[0]?.mode, "approved_write");
      assert.equal(row.rows[0]?.status, "succeeded");
      assert.equal(row.rows[0]?.approval_audit_id, approval.auditId);
      assert.equal(row.rows[0]?.item_count, "2");
      assert.equal(row.rows[0]?.applied_count, "1");
      assert.equal(row.rows[0]?.skipped_count, "1");

      const audit = await client.query<{ action: string; target_id: string }>(
        `
          select action, target_id
          from ingestion_platform.ingestion_audit_log
          where action = 'ship_staging_canary'
          order by id desc
          limit 1
        `
      );
      assert.equal(audit.rows[0]?.action, "ship_staging_canary");
      assert.equal(audit.rows[0]?.target_id, shipment.shipmentId);
    });
  }
);

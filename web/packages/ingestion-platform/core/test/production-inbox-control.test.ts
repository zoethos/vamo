import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { after, before, beforeEach, describe, it } from "node:test";
import { Client } from "pg";

import {
  recordProductionInboxApproval,
  recordProductionInboxDelivery
} from "../src/production-inbox-control.js";

const databaseUrl = process.env.INGESTION_TEST_DATABASE_URL;
const schemaSql = readFileSync("core/sql/control_schema.sql", "utf8");

describe(
  "production inbox control recorder",
  { skip: databaseUrl ? false : "Set INGESTION_TEST_DATABASE_URL for production-inbox control smoke." },
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

    it("records approval and production-inbox delivery ledger rows", async () => {
      const approval = await recordProductionInboxApproval({
        client,
        projectKey: "vamo",
        targetId: "vamo-place-intelligence-staging",
        accepted: true,
        actor: { type: "operator", id: "supabase:user-1" },
        reason: "first production inbox delivery",
        payload: { plan: { targetEnvironment: "production", write: { writeCount: 2 } } }
      });
      assert.ok(approval.auditId);

      const delivery = await recordProductionInboxDelivery({
        client,
        projectKey: "vamo",
        targetId: "vamo-place-intelligence-staging",
        targetAdapter: "postgres-production-inbox",
        approvalAuditId: approval.auditId!,
        packageId: `production-inbox:vamo-place-intelligence-staging:approval:${approval.auditId}`,
        packageChecksum: "checksum",
        itemCount: 2,
        actor: { type: "operator", id: "supabase:user-1" },
        reason: "first production inbox delivery"
      });
      assert.equal(delivery.ok, true);
      assert.ok(delivery.shipmentId);
      assert.ok(delivery.auditId);

      const row = await client.query<{
        shipment_key: string;
        status: string;
        environment: string;
        delivery_mode: string;
        production_status: string;
        item_count: number;
        package_id: string;
      }>(
        `
          select shipment_key,
                 status,
                 summary->>'environment' as environment,
                 summary->>'deliveryMode' as delivery_mode,
                 summary->>'productionStatus' as production_status,
                 (summary->>'itemCount')::int as item_count,
                 summary->>'packageId' as package_id
          from ingestion_platform.ingestion_shipments
          where id = $1::bigint
        `,
        [delivery.shipmentId]
      );
      assert.equal(
        row.rows[0]?.shipment_key,
        `production-inbox:vamo-place-intelligence-staging:approval:${approval.auditId}`
      );
      assert.equal(row.rows[0]?.status, "succeeded");
      assert.equal(row.rows[0]?.environment, "production");
      assert.equal(row.rows[0]?.delivery_mode, "consumer_inbox");
      assert.equal(row.rows[0]?.production_status, "production_inbox_delivered");
      assert.equal(row.rows[0]?.item_count, 2);
      assert.match(row.rows[0]?.package_id ?? "", /^production-inbox:/);

      const audit = await client.query<{ action: string; target_id: string }>(
        `
          select action, target_id
          from ingestion_platform.ingestion_audit_log
          where action = 'deliver_production_inbox'
          order by id desc
          limit 1
        `
      );
      assert.equal(audit.rows[0]?.action, "deliver_production_inbox");
      assert.equal(audit.rows[0]?.target_id, delivery.shipmentId);
    });
  }
);

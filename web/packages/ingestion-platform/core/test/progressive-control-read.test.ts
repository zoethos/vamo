import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";
import { Client, type QueryResult } from "pg";

import {
  loadProgressiveRunSnapshot,
  type ProgressiveControlReadPgClientLike
} from "../src/progressive-control-read.js";
import {
  buildProgressiveRunView,
  sampleProgressiveRunSnapshot,
  sampleVamoProposal
} from "../src/progressive-read-model.js";

const controlSchemaSql = readFileSync("core/sql/control_schema.sql", "utf8");
const databaseUrl = process.env.INGESTION_TEST_DATABASE_URL;

// Rows as the control DB would return them: scorecard/proposal/run_report are the
// exact JSONB the platform core produced, round-tripped back as parsed objects.
const sampleProposalResult = sampleVamoProposal();
assert.equal(sampleProposalResult.ok, true);
const sampleProposal = sampleProposalResult.ok ? sampleProposalResult.proposal : null;

const stubRows = sampleProgressiveRunSnapshot.entries.map((entry) => ({
  targetKey: entry.scorecard.targetId,
  workStatus: entry.workStatus,
  tier: entry.tier,
  safetyMode: entry.safetyMode,
  scorecard: entry.scorecard,
  proposal: entry.workStatus === "review_required" ? sampleProposal : null,
  runReport: entry.report ?? null
}));

function toResult<T extends Record<string, unknown>>(rows: unknown[]): QueryResult<T> {
  return {
    rows: rows as T[],
    rowCount: rows.length,
    command: "SELECT",
    oid: 0,
    fields: []
  } as QueryResult<T>;
}

// Query-aware stub: the control read now issues a second query for the shipment
// ledger, so the stub must answer proposal vs. shipment queries distinctly.
class StubProgressiveClient implements ProgressiveControlReadPgClientLike {
  constructor(
    private readonly rows: unknown[],
    private readonly shipmentRows: unknown[] = []
  ) {}

  async query<T extends Record<string, unknown> = Record<string, unknown>>(
    sql: string
  ): Promise<QueryResult<T>> {
    if (sql.includes("ingestion_shipments")) {
      return toResult<T>(this.shipmentRows);
    }
    return toResult<T>(this.rows);
  }
}

class MissingTableClient implements ProgressiveControlReadPgClientLike {
  async query(): Promise<never> {
    const error = new Error('relation "ingestion_schedule_proposals" does not exist');
    (error as { code?: string }).code = "42P01";
    throw error;
  }
}

describe("progressive control read", () => {
  it("returns progressive proposal/report rows when present", async () => {
    const snapshot = await loadProgressiveRunSnapshot({
      client: new StubProgressiveClient(stubRows),
      projectKey: "vamo"
    });

    assert.ok(snapshot);
    assert.equal(snapshot.entries.length, 2);

    const review = snapshot.entries.find((entry) => entry.workStatus === "review_required");
    assert.ok(review);
    assert.ok(review.report, "review entry carries its run report");
    assert.equal(review.report.wroteToTarget, false);
    assert.equal(review.tier, "sample_dry_run");
    assert.equal(review.safetyMode, "dry_run");
    assert.deepEqual(review.canaryBounds, {
      geography: "rome-italy",
      category: "poi",
      maxRows: 2
    });
  });

  it("falls back gracefully when no progressive rows exist", async () => {
    const snapshot = await loadProgressiveRunSnapshot({
      client: new StubProgressiveClient([]),
      projectKey: "vamo"
    });
    assert.equal(snapshot, null);
  });

  it("falls back gracefully when the progressive table is absent", async () => {
    const snapshot = await loadProgressiveRunSnapshot({
      client: new MissingTableClient(),
      projectKey: "vamo"
    });
    assert.equal(snapshot, null);
  });

  it("attaches a succeeded staging-canary shipment to its proposal", async () => {
    const shipmentRows = [
      {
        shipmentKey: "staging-canary:vamo-place-intelligence-staging:approval:4",
        status: "succeeded",
        mode: "approved_write",
        createdAt: "2026-06-28T12:00:00.000Z",
        summary: { environment: "staging", approvalAuditId: 4 }
      }
    ];
    const snapshot = await loadProgressiveRunSnapshot({
      client: new StubProgressiveClient(stubRows, shipmentRows),
      projectKey: "vamo"
    });
    assert.ok(snapshot);

    const review = snapshot.entries.find(
      (entry) => entry.scorecard.targetId === "vamo-place-intelligence-staging"
    );
    assert.ok(review);
    assert.ok(review.canaryShipment, "review entry carries its shipment state");
    assert.equal(review.canaryShipment.status, "succeeded");
    assert.equal(review.canaryShipment.mode, "approved_write");
    assert.equal(
      review.canaryShipment.shipmentKey,
      "staging-canary:vamo-place-intelligence-staging:approval:4"
    );
    assert.equal(review.canaryShipment.approvalAuditId, "4");

    // The view surfaces the spent canary and moves the target forward to the
    // production-inbox approval instead of inviting a repeat canary approval.
    const view = buildProgressiveRunView(snapshot);
    const row = view.rows.find(
      (candidate) => candidate.targetId === "vamo-place-intelligence-staging"
    );
    assert.ok(row);
    assert.equal(row.canaryShipped, true);
    assert.match(row.nextApproval, /production inbox delivery/i);
    assert.doesNotMatch(view.nextAction, /Review vamo-place-intelligence-staging/);
    assert.match(view.nextAction, /ready for production inbox approval/i);
  });

  it("attaches a production-inbox delivery shipment to its proposal", async () => {
    const shipmentRows = [
      {
        shipmentKey: "production-inbox:vamo-place-intelligence-staging:approval:14",
        status: "succeeded",
        mode: "approved_write",
        createdAt: "2026-07-01T12:00:00.000Z",
        summary: {
          environment: "production",
          productionStatus: "production_inbox_delivered",
          approvalAuditId: 14,
          packageId: "production-inbox:vamo-place-intelligence-staging:approval:14",
          itemCount: 2
        }
      }
    ];
    const snapshot = await loadProgressiveRunSnapshot({
      client: new StubProgressiveClient(stubRows, shipmentRows),
      projectKey: "vamo"
    });
    assert.ok(snapshot);

    const view = buildProgressiveRunView(snapshot);
    const row = view.rows.find(
      (candidate) => candidate.targetId === "vamo-place-intelligence-staging"
    );
    assert.ok(row);
    assert.equal(row.productionInboxDelivered, true);
    assert.equal(row.productionInbox?.approvalAuditId, "14");
    assert.equal(row.productionInbox?.itemCount, 2);
    assert.match(row.nextApproval, /waiting for Vamo apply/i);
  });

  it("falls back to the approval id parsed from the shipment key", async () => {
    const shipmentRows = [
      {
        shipmentKey: "staging-canary:vamo-place-intelligence-staging:approval:9",
        status: "shipping",
        mode: "approved_write",
        createdAt: "2026-06-28T12:00:00.000Z",
        summary: {}
      }
    ];
    const snapshot = await loadProgressiveRunSnapshot({
      client: new StubProgressiveClient(stubRows, shipmentRows),
      projectKey: "vamo"
    });
    assert.ok(snapshot);
    const review = snapshot.entries.find(
      (entry) => entry.scorecard.targetId === "vamo-place-intelligence-staging"
    );
    assert.ok(review?.canaryShipment);
    assert.equal(review.canaryShipment.approvalAuditId, "9");
    assert.equal(review.canaryShipment.status, "shipping");
  });

  it("ignores a failed shipment so approval can still be requested", async () => {
    const shipmentRows = [
      {
        shipmentKey: "staging-canary:vamo-place-intelligence-staging:approval:7",
        status: "failed",
        mode: "approved_write",
        createdAt: "2026-06-28T12:00:00.000Z",
        summary: { approvalAuditId: 7 }
      }
    ];
    const snapshot = await loadProgressiveRunSnapshot({
      client: new StubProgressiveClient(stubRows, shipmentRows),
      projectKey: "vamo"
    });
    assert.ok(snapshot);
    const view = buildProgressiveRunView(snapshot);
    const row = view.rows.find(
      (candidate) => candidate.targetId === "vamo-place-intelligence-staging"
    );
    assert.ok(row);
    // A failed shipment is recorded but not active: the canary slot is unspent.
    assert.equal(row.canaryShipped, false);
    assert.ok(row.canaryShipment, "failed shipment still surfaced for context");
    assert.match(view.nextAction, /Review vamo-place-intelligence-staging/);
  });

  it("surfaces AI advisory, tier, stage, blockers, next approval, and the dry-run invariant", async () => {
    const snapshot = await loadProgressiveRunSnapshot({
      client: new StubProgressiveClient(stubRows),
      projectKey: "vamo"
    });
    assert.ok(snapshot);

    const view = buildProgressiveRunView(snapshot);

    const review = view.rows.find((row) => row.workStatus === "review_required");
    assert.ok(review);
    assert.equal(review.tier, "sample_dry_run");
    assert.equal(review.stage, "review_required");
    assert.ok(review.aiSummary.length > 0, "AI advisory summary present");
    assert.ok(review.aiConfidence, "AI advisory confidence present");
    assert.ok(review.aiRecommendedTier, "AI recommended tier present");
    assert.match(review.nextApproval, /approve/i);
    // Dry-run invariant: a progressive run never wrote to its target.
    assert.equal(review.wroteToTarget, false);
    assert.deepEqual(review.canaryBounds, {
      geography: "rome-italy",
      category: "poi",
      maxRows: 2
    });

    const blocked = view.rows.find((row) => row.workStatus === "blocked");
    assert.ok(blocked);
    assert.ok(blocked.blockers.length > 0, "blocked target surfaces blocking gates");

    assert.equal(view.summary.reviewRequired, 1);
    assert.equal(view.summary.blocked, 1);
    assert.match(view.nextAction, /review/i);
  });

  it(
    "round-trips a durable proposal row through disposable Postgres",
    { skip: databaseUrl ? false : "Set INGESTION_TEST_DATABASE_URL for DB smoke." },
    async () => {
      assert.ok(databaseUrl);
      const client = new Client({ connectionString: databaseUrl });
      await client.connect();

      try {
        await client.query("drop schema if exists ingestion_platform cascade");
        await client.query(controlSchemaSql);

        const projectResult = await client.query<{ id: string }>(
          `
            insert into ingestion_platform.ingestion_projects (project_key, display_name)
            values ('demo', 'Demo Project')
            returning id
          `
        );
        const projectId = Number(projectResult.rows[0]?.id);

        const sampleEntry = sampleProgressiveRunSnapshot.entries[0];
        assert.ok(sampleEntry?.report);

        await client.query(
          `
            insert into ingestion_platform.ingestion_schedule_proposals (
              project_id,
              target_key,
              source_key,
              work_status,
              tier,
              safety_mode,
              scorecard,
              proposal,
              run_report
            )
            values ($1, $2, $3, $4, $5, $6, $7, $8, $9)
          `,
          [
            projectId,
            sampleEntry.scorecard.targetId,
            sampleEntry.scorecard.sourceId,
            sampleEntry.workStatus,
            sampleEntry.tier,
            sampleEntry.safetyMode,
            sampleEntry.scorecard,
            sampleProposal,
            sampleEntry.report
          ]
        );

        const snapshot = await loadProgressiveRunSnapshot({ client, projectKey: "demo" });
        assert.ok(snapshot);
        assert.equal(snapshot.entries.length, 1);

        const view = buildProgressiveRunView(snapshot);
        const row = view.rows[0];
        assert.ok(row);
        assert.equal(row.workStatus, "review_required");
        assert.equal(row.stage, "review_required");
        assert.equal(row.wroteToTarget, false);
        assert.deepEqual(row.canaryBounds, {
          geography: "rome-italy",
          category: "poi",
          maxRows: 2
        });
        assert.ok(row.aiSummary.length > 0);
        // No shipment ledger row yet: the canary slot is unspent.
        assert.equal(row.canaryShipped, false);
        assert.equal(row.canaryShipment, undefined);

        // Record a succeeded staging-canary shipment and confirm the join lights
        // up the proposal as already shipped.
        const targetResult = await client.query<{ id: string }>(
          `
            insert into ingestion_platform.ingestion_targets (
              project_id, target_key, display_name, adapter, safety_mode
            )
            values ($1, $2, $2, 'postgres-staging-canary', 'approved_write')
            returning id::text as id
          `,
          [projectId, sampleEntry.scorecard.targetId]
        );
        const targetId = Number(targetResult.rows[0]?.id);
        await client.query(
          `
            insert into ingestion_platform.ingestion_shipments (
              project_id, target_id, shipment_key, mode, status, summary
            )
            values ($1, $2, $3, 'approved_write', 'succeeded', $4::jsonb)
          `,
          [
            projectId,
            targetId,
            `staging-canary:${sampleEntry.scorecard.targetId}:approval:4`,
            JSON.stringify({ environment: "staging", approvalAuditId: 4 })
          ]
        );

        const shippedSnapshot = await loadProgressiveRunSnapshot({ client, projectKey: "demo" });
        assert.ok(shippedSnapshot);
        const shippedView = buildProgressiveRunView(shippedSnapshot);
        const shippedRow = shippedView.rows[0];
        assert.ok(shippedRow);
        assert.equal(shippedRow.canaryShipped, true);
        assert.ok(shippedRow.canaryShipment);
        assert.equal(shippedRow.canaryShipment.status, "succeeded");
        assert.equal(shippedRow.canaryShipment.approvalAuditId, "4");
        assert.match(shippedView.nextAction, /ready for production inbox approval/i);

        // Unknown project still falls back (null), exercising the join filter.
        const missing = await loadProgressiveRunSnapshot({ client, projectKey: "nope" });
        assert.equal(missing, null);
      } finally {
        await client.query("drop schema if exists ingestion_platform cascade");
        await client.end();
      }
    }
  );
});

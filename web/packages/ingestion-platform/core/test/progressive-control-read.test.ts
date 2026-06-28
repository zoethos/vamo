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
  workStatus: entry.workStatus,
  tier: entry.tier,
  safetyMode: entry.safetyMode,
  scorecard: entry.scorecard,
  proposal: entry.workStatus === "review_required" ? sampleProposal : null,
  runReport: entry.report ?? null
}));

class StubProgressiveClient implements ProgressiveControlReadPgClientLike {
  constructor(private readonly rows: unknown[]) {}

  async query<T extends Record<string, unknown> = Record<string, unknown>>(): Promise<
    QueryResult<T>
  > {
    return {
      rows: this.rows as T[],
      rowCount: this.rows.length,
      command: "SELECT",
      oid: 0,
      fields: []
    } as QueryResult<T>;
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

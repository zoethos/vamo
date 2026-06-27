import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";
import type { QueryResult } from "pg";

import { planPostgresDryRun, type PgClientLike } from "../../adapters/target/src/postgres-dry-run.js";
import { parsePipelineSpec, parseTargetProjectSpec } from "../../spec/src/index.js";
import { runFixturePipeline } from "../src/pipeline-runner.js";
import { buildScheduleProposal } from "../src/schedule-proposal.js";
import {
  evaluatePreflight,
  runProgressiveDryRun,
  type ProgressiveDryRunDeps
} from "../src/progressive-run.js";
import { scoreTargetCandidate, type TargetCandidateInput } from "../src/target-scorecard.js";

const bundleDir = "fixtures/imported/vamo-place-intelligence";
const fixture = JSON.parse(
  readFileSync("fixtures/platform/ip14/proposal-input.json", "utf8")
) as { candidates: TargetCandidateInput[] };
const vamoTarget = fixture.candidates[0];

function readSpecs() {
  const pipeline = parsePipelineSpec(readFileSync(`${bundleDir}/pipeline.yaml`, "utf8"));
  const target = parseTargetProjectSpec(readFileSync(`${bundleDir}/target.yaml`, "utf8"));
  if (!pipeline.ok || !target.ok) {
    throw new Error("IP-14 imported specs did not parse.");
  }
  return { pipeline: pipeline.value, target: target.value };
}

function buildIp14Proposal() {
  const scorecard = scoreTargetCandidate(vamoTarget);
  const result = buildScheduleProposal({
    scorecard,
    tier: "sample_dry_run",
    safetyMode: "dry_run",
    // Process the full bounded sample so the diff surfaces a policy block and a dead letter.
    scope: { geography: "rome-italy", category: "poi", rowLimit: 5 },
    batchSize: 2,
    checkpointEveryRows: 2,
    quotaBudget: { maxRows: 5, maxSourceCalls: 1, maxRuntimeSeconds: 30, maxFailures: 1 },
    runWindow: { earliestStart: "2026-06-28T00:00:00Z", latestStop: "2026-06-28T23:59:59Z" },
    stopConditions: {
      maxPolicyBlockRate: 0.5,
      maxDeadLetterRate: 0.5,
      maxCollisionRate: 0.2,
      stopOnSchemaMismatch: true,
      stopOnTargetWriteFailure: true,
      honorOperatorPause: true
    },
    forbidNonDryRun: true
  });
  if (!result.ok) {
    throw new Error(`IP-14 proposal did not build: ${JSON.stringify(result.errors)}`);
  }
  return { scorecard, proposal: result.proposal };
}

function makeDeps(): ProgressiveDryRunDeps {
  return {
    runPipeline: (input) => runFixturePipeline(input),
    planDryRun: ({ target, candidates }) =>
      planPostgresDryRun({ client: new VamoPlaceSchemaClient(), target, candidates })
  };
}

describe("progressive dry run", () => {
  it("passes preflight for the imported Vamo dry-run target", () => {
    const { pipeline, target } = readSpecs();
    const { scorecard } = buildIp14Proposal();
    const preflight = evaluatePreflight({ scorecard, pipeline, target });

    assert.equal(preflight.passed, true, JSON.stringify(preflight.failures));
    assert.ok(preflight.checks.find((check) => check.id === "dry_run_only")?.passed);
    assert.ok(preflight.checks.find((check) => check.id === "attribution")?.passed);
  });

  it("produces a shipment diff and checkpoint report without target writes", async () => {
    const { pipeline, target } = readSpecs();
    const { scorecard, proposal } = buildIp14Proposal();

    const report = await runProgressiveDryRun(
      { proposal, scorecard, pipeline, target, fixtureRoot: bundleDir },
      makeDeps()
    );

    // Stages move preflight -> scout -> sample_dry_run -> review_required.
    assert.deepEqual(
      report.stages.map((stage) => stage.stage),
      ["preflight", "scout", "sample_dry_run", "review_required"]
    );
    assert.equal(report.currentStage, "review_required");

    // Shipment diff produced, all inserts against an empty target, no writes.
    assert.equal(report.wroteToTarget, false);
    assert.equal(report.shipmentDiff.compatible, true);
    assert.equal(report.shipmentDiff.insert, 6);
    assert.equal(report.shipmentDiff.update, 0);
    assert.equal(report.shipmentDiff.total, 6);

    // Checkpoint report reflects the full bounded sample.
    assert.equal(report.checkpoint.processedCount, 5);
    assert.equal(report.checkpoint.lastRecordKey, "fsq_sagrada_familia");
    assert.equal(report.checkpoint.cursorScope, "source_row_id");

    // Row counts, policy blocks, and dead letters are surfaced.
    assert.equal(report.rowCounts.read, 5);
    assert.equal(report.rowCounts.staged, 3);
    assert.ok(report.deadLetters.length >= 1);
    assert.ok(report.policyBlocks.length >= 1);

    // The next required approval is explicit.
    assert.equal(report.nextApproval.requireMfa, true);
    assert.match(report.nextApproval.description, /staging canary/i);
  });

  it("blocks at sample_dry_run and offers no promotion path when the diff is incompatible", async () => {
    const { pipeline, target } = readSpecs();
    const { scorecard, proposal } = buildIp14Proposal();

    const report = await runProgressiveDryRun(
      { proposal, scorecard, pipeline, target, fixtureRoot: bundleDir },
      {
        runPipeline: (input) => runFixturePipeline(input),
        // Target tables do not exist -> incompatible dry-run diff.
        planDryRun: ({ target: dryRunTarget, candidates }) =>
          planPostgresDryRun({ client: new MissingTableClient(), target: dryRunTarget, candidates })
      }
    );

    assert.equal(report.shipmentDiff.compatible, false);
    assert.equal(report.reachedReview, false);
    assert.equal(report.currentStage, "sample_dry_run");
    assert.ok(!report.stages.some((stage) => stage.stage === "review_required"));
    assert.equal(
      report.stages.find((stage) => stage.stage === "sample_dry_run")?.status,
      "blocked"
    );
    // No promotion is offered for a failed diff: the approval differs from the
    // proposal's staging-canary approval and instructs the operator to resolve it.
    assert.notEqual(report.nextApproval.description, proposal.approval.description);
    assert.match(report.nextApproval.description, /^Resolve/);
    assert.match(report.nextApproval.description, /incompatibilit/i);
  });

  it("refuses any non-dry-run safety mode", async () => {
    const { pipeline, target } = readSpecs();
    const { scorecard, proposal } = buildIp14Proposal();
    const unsafe = { ...proposal, safetyMode: "staging_write" as const };

    await assert.rejects(
      runProgressiveDryRun(
        { proposal: unsafe, scorecard, pipeline, target, fixtureRoot: bundleDir },
        makeDeps()
      ),
      /dry_run only/
    );
  });
});

// Mirrors Z:\vamo\supabase\migrations\20260625155733_place_intelligence_cache.sql.
const vamoPlaceColumns: Record<string, string[]> = {
  location_canonicals: [
    "id",
    "canonical_key",
    "display_name",
    "name_norm",
    "feature_type",
    "country_code",
    "admin1",
    "latitude",
    "longitude",
    "source_provider",
    "source_place_id",
    "source_rank",
    "attribution",
    "confidence",
    "promotion_state",
    "created_at",
    "updated_at"
  ],
  location_source_refs: [
    "id",
    "canonical_id",
    "provider",
    "source_place_id",
    "source_payload_hash",
    "attribution",
    "fetched_at",
    "expires_at",
    "created_at"
  ]
};

class VamoPlaceSchemaClient implements PgClientLike {
  async query<T extends Record<string, unknown> = Record<string, unknown>>(
    sql: string,
    values?: unknown[]
  ): Promise<QueryResult<T>> {
    if (sql.includes("information_schema.tables")) {
      const table = String(values?.[1]);
      return this.result([{ exists: table in vamoPlaceColumns } as unknown as T]);
    }
    if (sql.includes("information_schema.columns")) {
      const table = String(values?.[1]);
      return this.result(
        (vamoPlaceColumns[table] ?? []).map((column) => ({ column_name: column }) as unknown as T)
      );
    }
    return this.result([]);
  }

  private result<T extends Record<string, unknown>>(rows: T[]): QueryResult<T> {
    return {
      rows,
      rowCount: rows.length,
      command: "SELECT",
      oid: 0,
      fields: []
    } as QueryResult<T>;
  }
}

class MissingTableClient implements PgClientLike {
  async query<T extends Record<string, unknown> = Record<string, unknown>>(
    sql: string
  ): Promise<QueryResult<T>> {
    if (sql.includes("information_schema.tables")) {
      return this.result([{ exists: false } as unknown as T]);
    }
    return this.result([]);
  }

  private result<T extends Record<string, unknown>>(rows: T[]): QueryResult<T> {
    return {
      rows,
      rowCount: rows.length,
      command: "SELECT",
      oid: 0,
      fields: []
    } as QueryResult<T>;
  }
}

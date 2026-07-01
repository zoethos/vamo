// IP-14 progressive dry-run harness.
//
// Runs the first Vamo progressive dry run end-to-end, in dry_run mode only, and
// prints a readable operator summary. It uses ONLY bundled data:
//   - the pinned consumer contract at fixtures/imported/vamo-place-intelligence
//   - the IP-14 candidate/proposal facts at fixtures/platform/ip14
//
// Guarantees:
//   - No secrets required.
//   - No connection to Vamo staging/production (the dry-run target schema is the
//     bundled, in-memory shape; nothing is written anywhere).
//   - No live provider or AI calls (AI rationale is the deterministic placeholder).
//   - Hard-fails (exit 1) if the proposal safety mode is anything but dry_run.
//
// Usage:
//   npm --workspace @confluendo/ingestion-platform run ip14:dry-run
//
// Requires a prior build (the npm script runs `build` first); it imports the
// compiled platform from dist/.

import { readFileSync } from "node:fs";
import { dirname, isAbsolute, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import {
  buildScheduleProposal,
  runFixturePipeline,
  runProgressiveDryRun,
  scoreTargetCandidate
} from "../dist/core/src/index.js";
import { planPostgresDryRun } from "../dist/adapters/target/src/index.js";
import {
  parsePipelineSpec,
  parseTargetProjectSpec
} from "../dist/spec/src/index.js";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const packageRoot = resolve(scriptDir, "..");
const bundleDir = resolve(packageRoot, "fixtures/imported/vamo-place-intelligence");
const proposalInputPath = resolve(packageRoot, "fixtures/platform/ip14/proposal-input.json");

// Bundled Vamo place-cache target shape. Mirrors
// Z:\vamo\supabase\migrations\20260625155733_place_intelligence_cache.sql. The
// harness never reaches a real database; this describes the dry-run target so
// the shipment diff can be planned offline.
const VAMO_PLACE_COLUMNS = {
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

/** Offline pg client: answers schema introspection from the bundled shape and
 *  returns no existing rows. It cannot perform any write. */
class BundledTargetSchemaClient {
  async query(sql, values) {
    if (sql.includes("information_schema.tables")) {
      const table = String(values?.[1]);
      return this.result([{ exists: table in VAMO_PLACE_COLUMNS }]);
    }
    if (sql.includes("information_schema.columns")) {
      const table = String(values?.[1]);
      return this.result((VAMO_PLACE_COLUMNS[table] ?? []).map((column) => ({ column_name: column })));
    }
    return this.result([]);
  }

  result(rows) {
    return { rows, rowCount: rows.length, command: "SELECT", oid: 0, fields: [] };
  }
}

function readBundle(relativePath) {
  const target = isAbsolute(relativePath) ? relativePath : resolve(bundleDir, relativePath);
  return readFileSync(target, "utf8");
}

function loadSpecs() {
  const pipeline = parsePipelineSpec(readBundle("pipeline.yaml"));
  const target = parseTargetProjectSpec(readBundle("target.yaml"));
  if (!pipeline.ok) {
    throw new Error(`Imported pipeline did not parse: ${JSON.stringify(pipeline.errors)}`);
  }
  if (!target.ok) {
    throw new Error(`Imported target did not parse: ${JSON.stringify(target.errors)}`);
  }
  return { pipeline: pipeline.value, target: target.value };
}

function bullet(label, value) {
  console.log(`  ${label.padEnd(22)} ${value}`);
}

function listOrNone(label, items) {
  if (!items || items.length === 0) {
    console.log(`  ${label.padEnd(22)} none`);
    return;
  }
  console.log(`  ${label}`);
  for (const item of items) {
    console.log(`    - ${item}`);
  }
}

async function main() {
  const input = JSON.parse(readFileSync(proposalInputPath, "utf8"));
  const candidate = input.candidates.find((entry) => entry.targetId === input.primaryTargetId);
  if (!candidate) {
    throw new Error(`IP-14 fixture has no candidate matching primaryTargetId "${input.primaryTargetId}".`);
  }

  const { pipeline, target } = loadSpecs();
  const scorecard = scoreTargetCandidate(candidate);

  const proposalResult = buildScheduleProposal({
    scorecard,
    tier: input.tier,
    safetyMode: input.safetyMode,
    scope: input.scope,
    batchSize: input.batchSize,
    checkpointEveryRows: input.checkpointEveryRows,
    quotaBudget: input.quotaBudget,
    runWindow: input.runWindow,
    stopConditions: input.stopConditions,
    forbidNonDryRun: true
  });

  if (!proposalResult.ok) {
    console.error("IP-14 schedule proposal was rejected:");
    for (const error of proposalResult.errors) {
      console.error(`  - [${error.code}] ${error.message}`);
    }
    process.exit(1);
  }

  const proposal = proposalResult.proposal;

  // Defense in depth: the orchestrator also refuses non-dry-run modes, but fail
  // loudly here before any work begins.
  if (proposal.safetyMode !== "dry_run") {
    console.error(`Refusing to run: safety mode is "${proposal.safetyMode}", expected "dry_run".`);
    process.exit(1);
  }

  const report = await runProgressiveDryRun(
    { proposal, scorecard, pipeline, target, fixtureRoot: bundleDir },
    {
      runPipeline: (pipelineInput) => runFixturePipeline(pipelineInput),
      planDryRun: ({ target: dryRunTarget, candidates }) =>
        planPostgresDryRun({ client: new BundledTargetSchemaClient(), target: dryRunTarget, candidates })
    }
  );

  const stageById = new Map(report.stages.map((stage) => [stage.stage, stage]));

  console.log("");
  console.log("=== IP-14 First Vamo Progressive Dry Run ===");
  console.log("(bundled fixtures only · dry_run · no writes · no live providers/AI)");
  console.log("");

  console.log("Selected target");
  bullet("project", report.projectKey);
  bullet("target", report.targetId);
  bullet("source", report.sourceId);
  bullet("eligible", String(scorecard.eligibleForScheduling));
  console.log("");

  console.log("Score and rationale");
  bullet("score", String(scorecard.score));
  bullet("ai confidence", report.aiRationale.confidence);
  bullet("rationale", scorecard.rationale);
  bullet("ai (advisory)", report.aiRationale.summary);
  console.log("");

  console.log("Tier and stage");
  bullet("tier", proposal.tier);
  bullet("safety_mode", proposal.safetyMode);
  bullet("current stage", report.currentStage);
  bullet("scope", `${proposal.scope.geography} / ${proposal.scope.category} / rowLimit=${proposal.scope.rowLimit}`);
  console.log("");

  console.log("Stages");
  bullet("preflight", `${stageById.get("preflight")?.status} — ${stageById.get("preflight")?.detail}`);
  bullet("scout", `${stageById.get("scout")?.status} — ${report.scout.detail}`);
  bullet("sample_dry_run", `${stageById.get("sample_dry_run")?.status} — ${stageById.get("sample_dry_run")?.detail}`);
  bullet("review_required", `${stageById.get("review_required")?.status} — ${stageById.get("review_required")?.detail}`);
  console.log("");

  console.log("Shipment diff (dry run — nothing written)");
  bullet("compatible", String(report.shipmentDiff.compatible));
  bullet("insert", String(report.shipmentDiff.insert));
  bullet("update", String(report.shipmentDiff.update));
  bullet("no-op", String(report.shipmentDiff.noOp));
  bullet("delete", String(report.shipmentDiff.delete));
  bullet("incompatibilities", String(report.shipmentDiff.incompatibilities));
  bullet("wrote to target", String(report.wroteToTarget));
  console.log("");

  console.log("Checkpoint report");
  bullet("cursor scope", report.checkpoint.cursorScope);
  bullet("cursor value", String(report.checkpoint.cursorValue));
  bullet("last record key", String(report.checkpoint.lastRecordKey));
  bullet("processed count", String(report.checkpoint.processedCount));
  console.log("");

  console.log("Row counts");
  bullet("read", String(report.rowCounts.read));
  bullet("staged", String(report.rowCounts.staged));
  bullet("policy blocked", String(report.rowCounts.policyBlocked));
  bullet("dead lettered", String(report.rowCounts.deadLettered));
  console.log("");

  listOrNone("Policy blocks", report.policyBlocks);
  listOrNone("Dead letters", report.deadLetters);
  console.log("");

  console.log("Next required approval");
  bullet("required", String(report.nextApproval.required));
  bullet("role", report.nextApproval.role);
  bullet("MFA", String(report.nextApproval.requireMfa));
  bullet("audit reason", String(report.nextApproval.requireAuditReason));
  bullet("description", report.nextApproval.description);
  console.log("");

  if (report.wroteToTarget !== false) {
    console.error("Invariant violated: dry run reported a target write.");
    process.exit(1);
  }

  // Treat a blocked or incomplete dry run as a failure so CI/operators do not
  // read a rejected run as success.
  const blockedStages = report.stages.filter((stage) => stage.status === "blocked");
  const succeeded =
    report.preflight.passed &&
    report.reachedReview &&
    report.currentStage === "review_required" &&
    report.shipmentDiff.compatible &&
    blockedStages.length === 0;

  if (!succeeded) {
    console.error(
      `IP-14 dry run did not complete cleanly (stage: ${report.currentStage}, ` +
        `preflight: ${report.preflight.passed}, compatible: ${report.shipmentDiff.compatible}` +
        (blockedStages.length > 0
          ? `, blocked: ${blockedStages.map((stage) => stage.stage).join(", ")}`
          : "") +
        "). Resolve blockers before any promotion."
    );
    process.exit(1);
  }

  console.log("IP-14 dry run complete. No staging/production writes. Operator approval required to proceed.");
}

main().catch((error) => {
  console.error("IP-14 dry-run harness failed:");
  console.error(error instanceof Error ? error.stack ?? error.message : error);
  process.exit(1);
});

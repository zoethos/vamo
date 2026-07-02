import assert from "node:assert/strict";
import { describe, it } from "node:test";

import type { AdminPrincipal } from "../src/admin-auth.js";
import {
  buildBatchQueueSnapshotFromItems,
  type BatchQueueItem
} from "../src/batch-queue-read-model.js";
import {
  countStagingCanaryWaveEligibleUnits,
  evaluateBatchStagingCanaryWaveApproval,
  type BatchStagingCanaryWaveBlockCode
} from "../src/batch-staging-canary-wave-policy.js";
import { STAGING_CANARY_MAX_ROWS } from "../src/staging-canary-policy.js";

const NOW = "2026-07-02T14:00:00.000Z";
const FRESH = "2026-07-02T13:58:00.000Z";
const STALE = "2026-07-02T12:00:00.000Z";

describe("evaluateBatchStagingCanaryWaveApproval", () => {
  it("accepts admin + AAL2 + fresh step-up for bounded dry_run_succeeded units", () => {
    const result = evaluateBatchStagingCanaryWaveApproval(validInput());
    assert.equal(result.ok, true);
    if (!result.ok) return;
    assert.equal(result.plan.targetEnvironment, "staging");
    assert.equal(result.plan.unitKeys.length, 1);
    assert.equal(result.plan.maxUnits, 1);
    assert.equal(result.plan.maxRows, 50);
    assert.match(result.plan.waveKey, /^batch-staging-canary:/);
  });

  it("blocks production environment", () => {
    const result = evaluateBatchStagingCanaryWaveApproval(
      validInput({ targetEnvironment: "production" })
    );
    assertBlocked(result, "production_environment_forbidden");
  });

  it("blocks operator role — admin required", () => {
    const result = evaluateBatchStagingCanaryWaveApproval(
      validInput({
        principal: adminPrincipal({ role: "operator" })
      })
    );
    assertBlocked(result, "role_denied");
  });

  it("blocks without verified AAL2", () => {
    const result = evaluateBatchStagingCanaryWaveApproval(
      validInput({
        principal: adminPrincipal({ assuranceLevel: "aal1" })
      })
    );
    assertBlocked(result, "mfa_required");
  });

  it("blocks without fresh MFA step-up", () => {
    const result = evaluateBatchStagingCanaryWaveApproval(
      validInput({
        principal: adminPrincipal({ stepUpSatisfiedAt: STALE })
      })
    );
    assertBlocked(result, "fresh_step_up_required");
  });

  it("blocks missing dry-run reports on dry_run_succeeded units", () => {
    const snapshot = snapshotWithItems([succeededItem("unit-a", { dryRunReport: null })]);
    const result = evaluateBatchStagingCanaryWaveApproval(validInput({ snapshot, maxUnits: 1 }));
    assertBlocked(result, "dry_run_report_missing");
  });

  it("blocks dry-run reports with wroteToTarget != false", () => {
    const snapshot = snapshotWithItems([
      succeededItem("unit-a", {
        dryRunReport: {
          wroteToTarget: true as unknown as false,
          rowsProcessed: 1,
          insertCount: 1,
          updateCount: 0,
          noOpCount: 0
        }
      })
    ]);
    const result = evaluateBatchStagingCanaryWaveApproval(validInput({ snapshot }));
    assertBlocked(result, "dry_run_invariant_violated");
  });

  it("blocks when no dry_run_succeeded units exist", () => {
    const snapshot = snapshotWithItems([
      {
        ...succeededItem("unit-a"),
        status: "dry_run_ready"
      }
    ]);
    const result = evaluateBatchStagingCanaryWaveApproval(validInput({ snapshot }));
    assertBlocked(result, "no_eligible_items");
  });

  it("respects maxUnits and maxRows bounds", () => {
    const snapshot = snapshotWithItems([
      { ...succeededItem("already-staged"), status: "staging_canary_succeeded" },
      succeededItem("unit-a", { writeCount: 10 }),
      succeededItem("unit-b", { writeCount: 10 }),
      succeededItem("unit-c", { writeCount: 10 })
    ]);
    const result = evaluateBatchStagingCanaryWaveApproval(
      validInput({ snapshot, maxUnits: 2, maxRows: 15 })
    );
    assert.equal(result.ok, true);
    if (!result.ok) return;
    assert.equal(result.plan.unitKeys.length, 1);
    assert.equal(result.plan.totalPlannedRows, 10);
  });

  it("refuses an oversized first live wave before any staging canary has succeeded", () => {
    const snapshot = snapshotWithItems([
      succeededItem("unit-a", { writeCount: 1 }),
      succeededItem("unit-b", { writeCount: 1 }),
      succeededItem("unit-c", { writeCount: 1 })
    ]);
    const result = evaluateBatchStagingCanaryWaveApproval(
      validInput({ snapshot, maxUnits: 33, maxRows: 50 })
    );
    assertBlocked(result, "ramp_exceeded");
  });

  it("counts eligible dry_run_succeeded units for dashboard visibility", () => {
    const snapshot = snapshotWithItems([
      succeededItem("unit-a"),
      succeededItem("unit-b", { dryRunReport: null }),
      { ...succeededItem("unit-c"), status: "dry_run_ready" }
    ]);
    assert.equal(countStagingCanaryWaveEligibleUnits(snapshot), 1);
  });
});

function validInput(
  overrides: Partial<Parameters<typeof evaluateBatchStagingCanaryWaveApproval>[0]> = {}
) {
  return {
    projectKey: "vamo",
    snapshot: snapshotWithItems([succeededItem("vamo-place-intelligence:rome-italy:poi")]),
    principal: adminPrincipal(),
    targetKey: "vamo-place-intelligence",
    targetEnvironment: "staging",
    maxUnits: 1,
    maxRows: STAGING_CANARY_MAX_ROWS,
    auditReason: "First bounded staging-canary wave approval smoke.",
    now: NOW,
    ...overrides
  };
}

function snapshotWithItems(items: BatchQueueItem[]) {
  return buildBatchQueueSnapshotFromItems({
    planId: "vamo-eu-poi-sample",
    projectKey: "vamo",
    targetKey: "vamo-place-intelligence",
    targetEnvironment: "staging",
    sourceKey: "fsq-os-places-sample",
    safetyMode: "dry_run",
    items
  });
}

function succeededItem(
  unitKey: string,
  options?: {
    dryRunReport?: BatchQueueItem["dryRunReport"];
    writeCount?: number;
  }
): BatchQueueItem {
  const writeCount = options?.writeCount ?? 3;
  return {
    unitKey,
    runOrder: unitKey.includes("rome") ? 1 : unitKey.includes("paris") ? 2 : 3,
    geography: "rome-italy",
    geographyKind: "city",
    country: "italy",
    category: "poi",
    targetKey: "vamo-place-intelligence",
    targetEnvironment: "staging",
    sourceKey: "fsq-os-places-sample",
    priority: 0,
    status: "dry_run_succeeded",
    blockReasons: [],
    dryRunReport:
      options?.dryRunReport === null
        ? null
        : (options?.dryRunReport ?? {
            wroteToTarget: false,
            rowsProcessed: writeCount,
            insertCount: writeCount,
            updateCount: 0,
            noOpCount: 0,
            source: "fixture_simulation"
          })
  };
}

function adminPrincipal(
  overrides: Partial<AdminPrincipal> = {}
): AdminPrincipal {
  return {
    provider: "supabase",
    userId: "admin-1",
    email: "admin@example.com",
    role: "admin",
    scopes: ["vamo"],
    mfaRequired: true,
    hasVerifiedMfaFactor: true,
    assuranceLevel: "aal2",
    stepUpSatisfiedAt: FRESH,
    ...overrides
  };
}

function assertBlocked(
  result: ReturnType<typeof evaluateBatchStagingCanaryWaveApproval>,
  code: BatchStagingCanaryWaveBlockCode
) {
  assert.equal(result.ok, false);
  if (result.ok) return;
  assert.ok(result.blocks.some((block) => block.code === code), `expected block ${code}`);
}

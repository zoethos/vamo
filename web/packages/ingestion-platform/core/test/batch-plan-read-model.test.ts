import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { buildBatchPlanView, sampleVamoEuPoiBatchView } from "../src/batch-plan-read-model.js";

describe("batch plan read model", () => {
  it("builds a dashboard preview from the bundled Vamo sample", () => {
    const view = sampleVamoEuPoiBatchView();
    assert.equal(view.planId, "vamo-eu-poi-sample");
    assert.equal(view.targetKey, "vamo-place-intelligence");
    assert.equal(view.targetEnvironment, "staging");
    assert.ok(view.totalUnits > 0);
    assert.equal(view.previewRows.length, 8);
    assert.match(view.nextAction, /review batch/i);
    assert.ok(Object.keys(view.coverage.perCountry).length > 0);
    assert.ok(Object.keys(view.coverage.perCategory).length > 0);
  });

  it("limits preview rows without changing totals", () => {
    const full = sampleVamoEuPoiBatchView();
    const limited = buildBatchPlanView(
      {
        planId: full.planId,
        projectKey: full.projectKey,
        targetKey: full.targetKey,
        targetEnvironment: full.targetEnvironment as "staging",
        sourceKey: full.sourceKey,
        safetyMode: "dry_run",
        totalUnits: full.totalUnits,
        plannedUnits: full.plannedUnits,
        blockedUnits: full.blockedUnits,
        units: full.rows.map((row, index) => ({
          unitKey: row.unitKey,
          runOrder: row.runOrder,
          projectKey: full.projectKey,
          targetId: full.targetKey,
          targetProfileKey: "place-intelligence",
          sourceId: full.sourceKey,
          targetEnvironment: "staging",
          geography: row.geography,
          geographyKind: "city",
          category: row.category,
          safetyMode: "dry_run",
          priority: row.priority,
          status: row.status as "planned",
          blockReasons: row.blockReasons,
          scope: {
            geography: row.geography,
            category: row.category,
            rowLimit: 50
          }
        })),
        coverage: full.coverage,
        nextAction: full.nextAction
      },
      3
    );
    assert.equal(limited.previewRows.length, 3);
    assert.equal(limited.totalUnits, full.totalUnits);
  });
});

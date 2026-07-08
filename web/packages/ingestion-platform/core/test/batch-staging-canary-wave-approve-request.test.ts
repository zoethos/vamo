import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, it } from "node:test";

import { parseBatchStagingCanaryWaveApproveRequest } from "../src/batch-staging-canary-wave-approve-request.js";

const testDir = dirname(fileURLToPath(import.meta.url));
const packageRoot = join(testDir, "..", "..", "..");
const webRoot = join(packageRoot, "..", "..");
const approveRoute = join(
  webRoot,
  "apps/confluendo-console/app/api/admin/ingestion/batch-canary-wave/approve/route.ts"
);

describe("parseBatchStagingCanaryWaveApproveRequest", () => {
  it("accepts optional unitKeys hints", () => {
    const parsed = parseBatchStagingCanaryWaveApproveRequest({
      targetKey: "vamo-place-intelligence",
      targetEnvironment: "staging",
      auditReason: "Approve selected scopes.",
      unitKeys: ["vamo-place-intelligence:paris-france:landmark"]
    });
    assert.equal(parsed.ok, true);
    if (!parsed.ok) return;
    assert.deepEqual(parsed.request.unitKeys, ["vamo-place-intelligence:paris-france:landmark"]);
  });

  it("dedupes unitKeys hints", () => {
    const parsed = parseBatchStagingCanaryWaveApproveRequest({
      targetKey: "vamo-place-intelligence",
      auditReason: "Approve selected scopes.",
      unitKeys: ["unit-a", "unit-a", " unit-b "]
    });
    assert.equal(parsed.ok, true);
    if (!parsed.ok) return;
    assert.deepEqual(parsed.request.unitKeys, ["unit-a", "unit-b"]);
  });
});

describe("batch staging-canary wave approve route artifact", () => {
  it("does not call staging write adapters from the approval route", () => {
    const routeSource = readFileSync(approveRoute, "utf8");
    assert.doesNotMatch(routeSource, /applyPostgresStagingCanary/);
    assert.doesNotMatch(routeSource, /executeBatchStagingCanaryWave/);
    assert.doesNotMatch(routeSource, /VAMO_STAGING_DATABASE_URL/);
    assert.match(routeSource, /approveBatchStagingCanaryWave/);
    assert.match(routeSource, /unitKeys/);
  });
});

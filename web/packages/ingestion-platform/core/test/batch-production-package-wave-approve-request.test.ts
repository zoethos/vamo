import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, it } from "node:test";

import { parseProductionPackageWaveApproveRequest } from "../src/batch-production-package-wave-approve-request.js";
import { VAMO_PRODUCTION_PACKAGE_SCHEMA_CONTRACT } from "../src/batch-production-package-wave-policy.js";

const testDir = dirname(fileURLToPath(import.meta.url));
const packageRoot = join(testDir, "..", "..", "..");
const webRoot = join(packageRoot, "..", "..");
const productionPackageWaveApproveRoute = join(
  webRoot,
  "apps/confluendo-console/app/api/admin/ingestion/production-package-wave/approve/route.ts"
);

describe("parseProductionPackageWaveApproveRequest", () => {
  it("accepts a valid production package-wave approval body", () => {
    const parsed = parseProductionPackageWaveApproveRequest({
      projectKey: "vamo",
      targetKey: "vamo-place-intelligence",
      targetEnvironment: "production",
      schemaContract: VAMO_PRODUCTION_PACKAGE_SCHEMA_CONTRACT,
      maxUnits: 1,
      maxRows: 10,
      maxPackages: 1,
      auditReason: "Approve first bounded package wave."
    });
    assert.equal(parsed.ok, true);
    if (!parsed.ok) return;
    assert.equal(parsed.request.targetEnvironment, "production");
    assert.equal(parsed.request.maxPackages, 1);
  });

  it("accepts optional unitKeys", () => {
    const parsed = parseProductionPackageWaveApproveRequest({
      targetKey: "vamo-place-intelligence",
      targetEnvironment: "production",
      auditReason: "Approve selected scopes.",
      unitKeys: ["unit-a", "unit-b"]
    });
    assert.equal(parsed.ok, true);
    if (!parsed.ok) return;
    assert.deepEqual(parsed.request.unitKeys, ["unit-a", "unit-b"]);
  });

  it("rejects staging target environment", () => {
    const parsed = parseProductionPackageWaveApproveRequest({
      targetKey: "vamo-place-intelligence",
      targetEnvironment: "staging",
      auditReason: "nope"
    });
    assert.equal(parsed.ok, false);
  });

  it("rejects schema contract mismatch", () => {
    const parsed = parseProductionPackageWaveApproveRequest({
      targetKey: "vamo-place-intelligence",
      targetEnvironment: "production",
      schemaContract: "vamo-place-intelligence@2",
      auditReason: "nope"
    });
    assert.equal(parsed.ok, false);
  });

  it("rejects missing audit reason", () => {
    const parsed = parseProductionPackageWaveApproveRequest({
      targetKey: "vamo-place-intelligence",
      targetEnvironment: "production"
    });
    assert.equal(parsed.ok, false);
  });
});

describe("production package-wave approve route artifact", () => {
  it("does not reference VAMO_PRODUCTION_INBOX_DATABASE_URL", () => {
    const routeSource = readFileSync(productionPackageWaveApproveRoute, "utf8");
    assert.doesNotMatch(routeSource, /VAMO_PRODUCTION_INBOX_DATABASE_URL/);
  });
});

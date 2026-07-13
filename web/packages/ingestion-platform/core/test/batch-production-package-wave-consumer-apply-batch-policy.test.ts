import assert from "node:assert/strict";
import { describe, it } from "node:test";

import {
  evaluateProductionPackageWaveBatchApply,
  resolveProductionPackageWaveBatchApplyTargets
} from "../src/batch-production-package-wave-consumer-apply-batch-policy.js";
import type { AdminPrincipal } from "../src/admin-auth.js";

const adminPrincipal: AdminPrincipal = {
  provider: "supabase",
  userId: "user-1",
  email: "admin@example.com",
  role: "admin",
  scopes: ["vamo"],
  assuranceLevel: "aal2",
  mfaRequired: true,
  hasVerifiedMfaFactor: true,
  stepUpSatisfiedAt: new Date().toISOString()
};

const pendingPreflight = {
  packageId: "pkg-1",
  shipmentStatus: "production_inbox_delivered",
  checksum: "abc",
  itemCount: 2,
  pendingItemCount: 2,
  targetTables: ["location_canonicals"],
  items: [
    {
      itemKey: "location_canonicals:1",
      targetTable: "location_canonicals",
      operation: "upsert",
      applyStatus: "pending",
      applyError: null
    }
  ],
  latestApplyLogResult: null,
  latestApplyLogDetail: null
};

describe("resolveProductionPackageWaveBatchApplyTargets", () => {
  it("skips already applied packages and keeps pending targets", () => {
    const resolved = resolveProductionPackageWaveBatchApplyTargets({
      wave: {
        waveKey: "wave-1",
        status: "delivered",
        items: [
          {
            unitKey: "unit-a",
            packageId: "pkg-1",
            status: "delivered",
            consumerApplyStatus: "pending"
          },
          {
            unitKey: "unit-b",
            packageId: "pkg-2",
            status: "consumer_applied",
            consumerApplyStatus: "applied"
          }
        ]
      },
      packageIds: ["pkg-1", "pkg-2"],
      prefetchesByPackageId: {
        "pkg-1": pendingPreflight,
        "pkg-2": {
          ...pendingPreflight,
          packageId: "pkg-2",
          shipmentStatus: "consumer_applied",
          pendingItemCount: 0,
          items: pendingPreflight.items.map((item) => ({ ...item, applyStatus: "applied" }))
        }
      }
    });
    assert.equal(resolved.targets.length, 1);
    assert.equal(resolved.skippedAppliedPackageIds.length, 1);
    assert.equal(resolved.targets[0]?.packageId, "pkg-1");
  });
});

describe("evaluateProductionPackageWaveBatchApply", () => {
  it("requires admin, fresh MFA, and audit reason", () => {
    const result = evaluateProductionPackageWaveBatchApply({
      projectKey: "vamo",
      waveKey: "wave-1",
      auditReason: "",
      principal: adminPrincipal,
      wave: { waveKey: "wave-1", status: "approved", items: [] },
      prefetchesByPackageId: {},
      applyDatabaseConfigured: true
    });
    assert.equal(result.ok, false);
    if (result.ok) return;
    assert.ok(result.blocks.some((block) => block.code === "audit_reason_required"));
    assert.ok(result.blocks.some((block) => block.code === "wave_not_deliverable"));
  });
});

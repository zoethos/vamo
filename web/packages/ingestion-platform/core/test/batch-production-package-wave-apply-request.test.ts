import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, it } from "node:test";

import {
  evaluateProductionPackageConsumerApply,
  evaluateProductionPackageConsumerApplyPreflight
} from "../src/batch-production-package-wave-consumer-apply-policy.js";
import {
  parseProductionPackageWaveApplyPreflightQuery,
  parseProductionPackageWaveApplyRequest
} from "../src/batch-production-package-wave-apply-request.js";
import type { AdminPrincipal } from "../src/admin-auth.js";

const testDir = dirname(fileURLToPath(import.meta.url));
const packageRoot = join(testDir, "..", "..", "..");
const webRoot = join(packageRoot, "..", "..");
const applyRoute = join(
  webRoot,
  "apps/confluendo-console/app/api/admin/ingestion/production-package-wave/apply/route.ts"
);
const applyWaveRoute = join(
  webRoot,
  "apps/confluendo-console/app/api/admin/ingestion/production-package-wave/apply-wave/route.ts"
);
const preflightRoute = join(
  webRoot,
  "apps/confluendo-console/app/api/admin/ingestion/production-package-wave/apply/preflight/route.ts"
);

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
  targetTables: ["location_canonicals", "location_source_refs"],
  items: [
    {
      itemKey: "location_canonicals:fsq-colosseum",
      targetTable: "location_canonicals",
      operation: "upsert",
      applyStatus: "pending",
      applyError: null
    },
    {
      itemKey: "location_source_refs:fsq_os_places:fsq_colosseum",
      targetTable: "location_source_refs",
      operation: "upsert",
      applyStatus: "pending",
      applyError: null
    }
  ],
  latestApplyLogResult: null,
  latestApplyLogDetail: null
};

describe("parseProductionPackageWaveApplyRequest", () => {
  it("accepts a valid apply body", () => {
    const parsed = parseProductionPackageWaveApplyRequest({
      projectKey: "vamo",
      packageId: "batch-production-inbox:pkg",
      auditReason: "Apply delivered package to Vamo."
    });
    assert.equal(parsed.ok, true);
  });

  it("rejects missing package id", () => {
    const parsed = parseProductionPackageWaveApplyRequest({
      auditReason: "missing package"
    });
    assert.equal(parsed.ok, false);
  });
});

describe("evaluateProductionPackageConsumerApplyPreflight", () => {
  it("accepts delivered packages with pending items", () => {
    const blocks = evaluateProductionPackageConsumerApplyPreflight(pendingPreflight);
    assert.deepEqual(blocks, []);
  });

  it("rejects already applied packages", () => {
    const blocks = evaluateProductionPackageConsumerApplyPreflight({
      ...pendingPreflight,
      shipmentStatus: "consumer_applied",
      pendingItemCount: 0,
      items: pendingPreflight.items.map((item) => ({ ...item, applyStatus: "applied" }))
    });
    assert.equal(blocks[0]?.code, "already_applied");
  });
});

describe("evaluateProductionPackageConsumerApply", () => {
  it("requires admin, audit reason, and configured apply database", () => {
    const decision = evaluateProductionPackageConsumerApply({
      projectKey: "vamo",
      packageId: "pkg-1",
      auditReason: "",
      principal: { ...adminPrincipal, role: "operator" },
      preflight: pendingPreflight,
      applyDatabaseConfigured: false
    });
    assert.equal(decision.ok, false);
    if (decision.ok) return;
    assert.ok(decision.blocks.some((block) => block.code === "role_denied"));
    assert.ok(decision.blocks.some((block) => block.code === "audit_reason_required"));
    assert.ok(decision.blocks.some((block) => block.code === "apply_not_configured"));
  });
});

describe("production package-wave apply route artifact", () => {
  it("does not reference VAMO_PRODUCTION_INBOX_DATABASE_URL", () => {
    const routeSource = readFileSync(applyRoute, "utf8");
    assert.doesNotMatch(routeSource, /VAMO_PRODUCTION_INBOX_DATABASE_URL/);
  });

  it("does not use telemetry database URL for apply execution", () => {
    const routeSource = readFileSync(applyRoute, "utf8");
    assert.doesNotMatch(routeSource, /VAMO_PRODUCTION_INBOX_TELEMETRY_DATABASE_URL/);
    const preflightSource = readFileSync(preflightRoute, "utf8");
    assert.doesNotMatch(preflightSource, /VAMO_PRODUCTION_INBOX_TELEMETRY_DATABASE_URL/);
  });

  it("uses read-only admin auth for preflight rather than the JSON mutation guard", () => {
    const preflightSource = readFileSync(preflightRoute, "utf8");
    assert.match(preflightSource, /authorizeIngestionReadRequest/);
    assert.doesNotMatch(preflightSource, /authorizeStagingCanaryRequest/);
  });

  it("does not insert or update Vamo product tables directly", () => {
    const routeSource = readFileSync(applyRoute, "utf8");
    assert.doesNotMatch(routeSource, /insert into public\.location_canonicals/i);
    assert.doesNotMatch(routeSource, /insert into public\.location_source_refs/i);
    assert.doesNotMatch(routeSource, /update public\.location_canonicals/i);
    assert.doesNotMatch(routeSource, /update public\.location_source_refs/i);
  });

  it("uses the dedicated apply database URL env var", () => {
    const routeSource = readFileSync(applyRoute, "utf8");
    assert.match(routeSource, /VAMO_PRODUCTION_INBOX_APPLY_DATABASE_URL/);
  });
});

describe("production package-wave apply-wave route artifact", () => {
  it("uses apply DSN only and refuses writer DSN", () => {
    const routeSource = readFileSync(applyWaveRoute, "utf8");
    assert.match(routeSource, /VAMO_PRODUCTION_INBOX_APPLY_DATABASE_URL/);
    assert.match(routeSource, /writer_dsn_present/);
    assert.doesNotMatch(routeSource, /insert into public\.location_canonicals/i);
  });

  it("delegates to batch apply orchestrator", () => {
    const routeSource = readFileSync(applyWaveRoute, "utf8");
    assert.match(routeSource, /executeProductionPackageWaveConsumerApplyBatch/);
  });
});

describe("parseProductionPackageWaveApplyPreflightQuery", () => {
  it("parses package id query params", () => {
    const parsed = parseProductionPackageWaveApplyPreflightQuery({
      packageId: "pkg-1",
      projectKey: "vamo"
    });
    assert.equal(parsed.ok, true);
    if (!parsed.ok) return;
    assert.equal(parsed.packageId, "pkg-1");
  });
});

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, it } from "node:test";
import {
  buildDeliveryWhatToDoNext,
  DELIVERY_APPLY_STATE_UNKNOWN_LABEL,
  DELIVERY_APPROVAL_ENVELOPE_EMPTY_COPY,
  DELIVERY_PARTIAL_BATCH_APPLY_COPY,
  DELIVERY_STATE_TERMINOLOGY,
  DELIVERY_WORKFLOW_STEPS,
  isDeliveredApplyStateUnknown,
  resolveDeliveryWorkflowHighlight
} from "../src/delivery-workflow-presenter.js";

const testDir = dirname(fileURLToPath(import.meta.url));
const packageRoot = join(testDir, "..", "..", "..");
const webRoot = join(packageRoot, "..", "..");
const guideComponentPath = join(
  webRoot,
  "apps/confluendo-console/app/admin/ingestion/delivery-workflow-guide.tsx"
);
const presenterPath = join(packageRoot, "core/src/delivery-workflow-presenter.ts");
const globalsCssPath = join(webRoot, "apps/confluendo-console/app/globals.css");

const REQUIRED_STATE_LABELS = [
  "Staging verified",
  "Eligible for package",
  "Package approved",
  "Delivered to inbox",
  "Apply pending",
  "Applied",
  "Blocked"
];

describe("delivery workflow presenter", () => {
  it("exposes all seven workflow step labels", () => {
    for (const label of REQUIRED_STATE_LABELS) {
      assert.ok(DELIVERY_WORKFLOW_STEPS.some((step) => step.label === label));
    }
  });

  it("includes telemetry-unknown and partial-apply recovery copy", () => {
    assert.match(DELIVERY_APPLY_STATE_UNKNOWN_LABEL, /apply state unknown/i);
    assert.ok(
      DELIVERY_STATE_TERMINOLOGY.some((row) => row.state === DELIVERY_APPLY_STATE_UNKNOWN_LABEL)
    );
    assert.match(DELIVERY_PARTIAL_BATCH_APPLY_COPY, /sequential, not atomic/i);
    assert.match(DELIVERY_PARTIAL_BATCH_APPLY_COPY, /Do not re-deliver/i);
  });

  it("resolves apply-state-unknown when telemetry is missing after delivery", () => {
    assert.equal(
      resolveDeliveryWorkflowHighlight({
        latestWaveStatus: "production_package_delivered",
        consumerApplyStatus: null,
        applyTelemetrySource: "missing",
        eligibleCount: 0,
        deliveredCount: 1,
        applyPendingCount: 0,
        appliedCount: 0,
        blockedCount: 0,
        hasLatestWave: true
      }),
      "apply_state_unknown"
    );
    assert.equal(
      isDeliveredApplyStateUnknown({
        latestWaveStatus: "production_package_delivered",
        consumerApplyStatus: null,
        applyTelemetrySource: "missing",
        eligibleCount: 0,
        deliveredCount: 1,
        applyPendingCount: 0,
        appliedCount: 0,
        blockedCount: 0,
        hasLatestWave: true
      }),
      true
    );
  });

  it("recommends refresh before retry when apply state is unknown", () => {
    const message = buildDeliveryWhatToDoNext({
      latestWaveStatus: "delivered",
      consumerApplyStatus: null,
      applyTelemetrySource: "missing",
      eligibleCount: 0,
      deliveredCount: 1,
      applyPendingCount: 0,
      appliedCount: 0,
      blockedCount: 0,
      hasLatestWave: true
    });
    assert.match(message, /Refresh delivery telemetry/i);
  });
});

describe("delivery workflow guide artifact", () => {
  it("does not use raw canary in operator copy", () => {
    const source = readFileSync(guideComponentPath, "utf8").toLowerCase();
    assert.doesNotMatch(source, /\bcanary\b/);
  });

  it("includes required state labels and partial-apply copy", () => {
    const guideSource = readFileSync(guideComponentPath, "utf8");
    const presenterSource = readFileSync(presenterPath, "utf8");
    for (const label of REQUIRED_STATE_LABELS) {
      assert.match(presenterSource, new RegExp(label.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")));
    }
    assert.match(presenterSource, /Delivered — apply state unknown/);
    assert.match(guideSource, /DELIVERY_PARTIAL_BATCH_APPLY_COPY/);
    assert.match(guideSource, /DELIVERY_STATE_TERMINOLOGY/);
  });

  it("keeps explicit empty approval-envelope copy in the presenter", () => {
    assert.match(DELIVERY_APPROVAL_ENVELOPE_EMPTY_COPY, /Select eligible scopes to preview the approval envelope/i);
  });
});

describe("delivery workflow guide dark-mode css", () => {
  it("covers guide panels and state table in dark theme", () => {
    const css = readFileSync(globalsCssPath, "utf8");
    assert.match(css, /\.admin-console\[data-theme="dark"\] \.admin-delivery-workflow-guide/);
    assert.match(css, /\.admin-console\[data-theme="dark"\] \.admin-delivery-workflow-step/);
    assert.match(css, /\.admin-console\[data-theme="dark"\] \.admin-delivery-workflow-table/);
  });
});

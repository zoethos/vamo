import assert from "node:assert/strict";
import { describe, it } from "node:test";

import {
  presentSnapshotCommissionCard,
  toSnapshotCommissionRequestSummary
} from "../src/snapshot-commission-presenter.js";
import type { SnapshotCommissionRequestRecord } from "../src/snapshot-commission-request.js";

const baseRequest: SnapshotCommissionRequestRecord = {
  requestId: "42",
  projectKey: "vamo",
  planKey: "vamo-eu-poi-sample",
  sourceKey: "fsq-os-places-snapshot",
  status: "requested",
  countries: ["italy"],
  categories: ["poi"],
  maxRowsPerScope: 250,
  auditReason: "Commission bounded snapshot.",
  requestedByType: "operator",
  requestedById: "dba@example.com",
  requestedAt: "2026-07-06T12:00:00.000Z"
};

describe("presentSnapshotCommissionCard", () => {
  it("presents the empty commissioning state", () => {
    const card = presentSnapshotCommissionCard({
      hasActiveRequest: false,
      defaultSourceKey: "fsq-os-places-snapshot",
      defaultCountries: ["italy", "france"],
      defaultCategories: ["poi", "landmark"],
      defaultMaxRowsPerScope: 250
    });

    assert.equal(card.hasRequest, false);
    assert.equal(card.status, "none");
    assert.equal(card.canCreateRequest, true);
    assert.match(card.nextHumanAction, /trusted worker/i);
  });

  for (const status of [
    "requested",
    "running",
    "release_registered",
    "activation_pending",
    "failed"
  ] as const) {
    it(`presents ${status} without secrets`, () => {
      const card = presentSnapshotCommissionCard({
        request: {
          ...baseRequest,
          status,
          registeredReleaseId:
            status === "release_registered" || status === "activation_pending"
              ? "fsq_os_places-20260701-deadbeefcafe"
              : undefined,
          errorCode: status === "failed" ? "acquisition_blocked" : undefined,
          errorMessage: status === "failed" ? "Acquisition was blocked." : undefined
        },
        hasActiveRequest: status !== "failed" && status !== "activation_pending",
        defaultSourceKey: "fsq-os-places-snapshot",
        defaultCountries: ["italy"],
        defaultCategories: ["poi"],
        defaultMaxRowsPerScope: 250
      });

      assert.equal(card.status, status);
      assert.ok(card.nextHumanAction.length > 0);
      assert.doesNotMatch(JSON.stringify(card), /artifact/i);
      assert.doesNotMatch(JSON.stringify(card), /s3/i);
      assert.doesNotMatch(JSON.stringify(card), /token/i);
      if (status === "activation_pending") {
        assert.match(card.nextHumanAction, /snapshot-activate/i);
        assert.match(card.recoveryHint ?? "", /never automatic/i);
      }
    });
  }
});

describe("toSnapshotCommissionRequestSummary", () => {
  it("omits worker run keys from safe summaries", () => {
    const summary = toSnapshotCommissionRequestSummary({
      ...baseRequest,
      workerRunKey: "secret-run-key"
    });

    assert.equal(summary.requestId, "42");
    assert.equal("workerRunKey" in summary, false);
  });
});

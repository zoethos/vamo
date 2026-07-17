import assert from "node:assert/strict";
import { describe, it } from "node:test";

import {
  describeSnapshotCommissionAcquisitionFailure,
  describeUnexpectedSnapshotCommissionFailure,
  stageForCommissionFailure
} from "../src/snapshot-commission-failure-telemetry.js";

describe("snapshot commission failure telemetry", () => {
  it("records a safe traceable stage for acquisition blocks", () => {
    const telemetry = describeSnapshotCommissionAcquisitionFailure({
      errorCode: "artifact_store_write_failed"
    });

    assert.match(telemetry.traceId, /^[a-f0-9-]{36}$/i);
    assert.equal(telemetry.stage, "artifact_store");
    assert.equal(telemetry.classification, "artifact_store_write_failed");
    assert.equal(telemetry.errorFingerprint, undefined);
  });

  it("classifies unexpected errors without retaining raw secrets", () => {
    const error = Object.assign(
      new Error(
        "unable to verify certificate for postgres://owner:password@db with FSQ_OS_PLACES_PORTAL_ACCESS_TOKEN=secret"
      ),
      { code: "CERT_HAS_EXPIRED" }
    );
    const telemetry = describeUnexpectedSnapshotCommissionFailure(error);
    const serialized = JSON.stringify(telemetry);

    assert.equal(telemetry.stage, "worker");
    assert.equal(telemetry.classification, "tls_trust_failure");
    assert.equal(telemetry.sourceErrorCode, "CERT_HAS_EXPIRED");
    assert.match(telemetry.errorFingerprint ?? "", /^[a-f0-9]{64}$/);
    assert.doesNotMatch(serialized, /postgres:|password|PORTAL_ACCESS_TOKEN|secret/i);
  });

  it("keeps the stage vocabulary deterministic", () => {
    assert.equal(stageForCommissionFailure("portal_query_timeout"), "portal");
    assert.equal(stageForCommissionFailure("release_registration_failed"), "release_registry");
    assert.equal(stageForCommissionFailure("source_mapping_requires_plan_refresh"), "contract");
  });
});

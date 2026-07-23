import assert from "node:assert/strict";
import { describe, it } from "node:test";

import {
  describeSnapshotActivationPreconditionFailure,
  describeUnexpectedSnapshotActivationFailure,
  stageForActivationFailure
} from "../src/snapshot-activation-failure-telemetry.js";

describe("snapshot activation failure telemetry", () => {
  it("records a safe traceable stage for activation preconditions", () => {
    const telemetry = describeSnapshotActivationPreconditionFailure({
      blocks: ["artifact_bundle_checksum_mismatch"]
    });

    assert.match(telemetry.traceId, /^[a-f0-9-]{36}$/i);
    assert.equal(telemetry.stage, "artifact_store");
    assert.equal(telemetry.classification, "artifact_bundle_checksum_mismatch");
    assert.equal(telemetry.errorFingerprint, undefined);
  });

  it("classifies unexpected worker errors without retaining raw secrets", () => {
    const error = Object.assign(
      new Error(
        "unable to verify certificate for postgres://owner:password@db with secret=opaque-value"
      ),
      { code: "CERT_HAS_EXPIRED" }
    );
    const telemetry = describeUnexpectedSnapshotActivationFailure(error);
    const serialized = JSON.stringify(telemetry);

    assert.equal(telemetry.stage, "worker");
    assert.equal(telemetry.classification, "tls_trust_failure");
    assert.equal(telemetry.sourceErrorCode, "CERT_HAS_EXPIRED");
    assert.match(telemetry.errorFingerprint ?? "", /^[a-f0-9]{64}$/);
    assert.doesNotMatch(serialized, /postgres:|password|opaque-value/i);
  });

  it("keeps activation failure stages deterministic", () => {
    assert.equal(stageForActivationFailure("artifact_store_unconfigured"), "artifact_store");
    assert.equal(stageForActivationFailure("release_not_activation_ready"), "release_registry");
    assert.equal(stageForActivationFailure("batch_queue_not_found"), "control_plane");
  });
});

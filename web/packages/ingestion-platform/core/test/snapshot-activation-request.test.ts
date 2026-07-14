import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";

import {
  SNAPSHOT_ACTIVATION_REQUEST_CONFIRMATION_STATE,
  canTransitionSnapshotActivationRequestStatus,
  parseSnapshotActivationRequestCreate
} from "../src/snapshot-activation-request.js";
import { evaluateSnapshotActivationRequestCreate } from "../src/snapshot-activation-request-policy.js";
import { presentSnapshotActivationCard } from "../src/snapshot-activation-request-presenter.js";
import {
  SNAPSHOT_ACTIVATION_WORKER_CONFIRMATION_VALUE,
  runSnapshotActivationWorker
} from "../src/snapshot-activation-worker.js";
import type { SnapshotCommissionRequestRecord } from "../src/snapshot-commission-request.js";

const routeSource = readFileSync(
  "../../apps/confluendo-console/app/api/admin/ingestion/snapshot-activation/request/route.ts",
  "utf8"
);
const workerSource = readFileSync("core/src/snapshot-activation-worker.ts", "utf8");

const activationPendingCommission: SnapshotCommissionRequestRecord = {
  requestId: "42",
  projectKey: "vamo",
  planKey: "vamo-eu-full-data-v1",
  sourceKey: "fsq-os-places-snapshot",
  status: "activation_pending",
  countries: ["italy"],
  categories: ["poi"],
  maxRowsPerScope: 250,
  auditReason: "Commission release.",
  requestedByType: "operator",
  requestedById: "admin@example.com",
  requestedAt: "2026-07-14T12:00:00.000Z",
  registeredReleaseId: "fsq_os_places-20260714-a1b2c3d4"
};

describe("snapshot activation request parser", () => {
  it("accepts the bounded request while ignoring forged plan and release hints", () => {
    const parsed = parseSnapshotActivationRequestCreate({
      projectKey: "vamo",
      planKey: "forged-plan",
      releaseId: "forged-release",
      auditReason: "Activate the reviewed snapshot release.",
      confirmedState: SNAPSHOT_ACTIVATION_REQUEST_CONFIRMATION_STATE
    });
    assert.equal(parsed.ok, true);
    if (!parsed.ok) return;
    assert.equal("planKey" in parsed.request, false);
    assert.equal("releaseId" in parsed.request, false);
  });

  it("requires the explicit activation confirmation", () => {
    const parsed = parseSnapshotActivationRequestCreate({
      projectKey: "vamo",
      auditReason: "Activate.",
      confirmedState: "activate_now"
    });
    assert.equal(parsed.ok, false);
    if (parsed.ok) return;
    assert.equal(parsed.code, "confirmed_state_mismatch");
  });
});

describe("snapshot activation request policy", () => {
  it("requires admin, fresh AAL2, activation readiness, and no active request", () => {
    const blocked = evaluateSnapshotActivationRequestCreate({
      actor: {
        type: "operator",
        id: "admin@example.com",
        role: "admin",
        assuranceLevel: "aal2",
        stepUpFresh: true
      },
      auditReason: "Activate reviewed release.",
      activationReady: false,
      hasActiveRequest: true
    });
    assert.equal(blocked.ok, false);
    if (blocked.ok) return;
    assert.deepEqual(
      blocked.blocks.map((block) => block.code),
      ["activation_not_ready", "activation_request_already_active"]
    );
  });
});

describe("snapshot activation request presenter", () => {
  it("keeps activation separate from commissioning and only enables it after a registered release is pending", () => {
    const waiting = presentSnapshotActivationCard({ hasActiveRequest: false });
    assert.equal(waiting.canCreateRequest, false);
    assert.match(waiting.nextHumanAction, /commissioning/i);

    const ready = presentSnapshotActivationCard({
      commissionRequest: activationPendingCommission,
      hasActiveRequest: false
    });
    assert.equal(ready.canCreateRequest, true);
    assert.equal(ready.releaseId, activationPendingCommission.registeredReleaseId);
    assert.match(ready.description, /separately approved/i);
  });

  it("does not let an older completed activation hide a newer registered release", () => {
    const card = presentSnapshotActivationCard({
      commissionRequest: activationPendingCommission,
      activationRequest: {
        requestId: "99",
        projectKey: "vamo",
        planKey: "vamo-eu-full-data-v1",
        commissionRequestId: "old-commission",
        releaseId: "old-release",
        status: "activated",
        auditReason: "Old activation.",
        requestedByType: "operator",
        requestedById: "admin@example.com",
        requestedAt: "2026-07-13T12:00:00.000Z"
      },
      hasActiveRequest: false
    });
    assert.equal(card.statusLabel, "Ready for approval");
    assert.equal(card.releaseId, activationPendingCommission.registeredReleaseId);
    assert.equal(card.canCreateRequest, true);
  });
});

describe("snapshot activation request lifecycle and boundary", () => {
  it("allows only worker-owned terminal transitions", () => {
    assert.equal(canTransitionSnapshotActivationRequestStatus("requested", "running"), true);
    assert.equal(canTransitionSnapshotActivationRequestStatus("running", "activated"), true);
    assert.equal(canTransitionSnapshotActivationRequestStatus("requested", "activated"), false);
    assert.equal(canTransitionSnapshotActivationRequestStatus("activated", "running"), false);
  });

  it("keeps the console route free of artifact stores and activation execution", () => {
    assert.doesNotMatch(routeSource, /runSnapshotReleaseActivation/);
    assert.doesNotMatch(routeSource, /snapshot-artifact-store/);
    assert.doesNotMatch(routeSource, /FSQ_OS_PLACES_CATALOG_TOKEN/);
    assert.match(workerSource, /runSnapshotReleaseActivation/);
  });

  it("refuses worker execution without its own explicit confirmation", async () => {
    const result = await runSnapshotActivationWorker({
      connectionString: "postgres://not-used",
      workerId: "worker",
      workerRunKey: "run",
      confirmation: "NO",
      artifactStore: {
        async putReleaseBundle() {
          throw new Error("not reached");
        },
        async readReleaseBundle() {
          throw new Error("not reached");
        },
        async verifyReleaseBundle() {
          throw new Error("not reached");
        }
      }
    });
    assert.equal(result.ok, false);
    if (result.ok) return;
    assert.match(result.blocks[0] ?? "", /CONFIRM_CONFLUENDO_SNAPSHOT_ACTIVATION_WORKER/);
    assert.notEqual(SNAPSHOT_ACTIVATION_WORKER_CONFIRMATION_VALUE, "NO");
  });
});

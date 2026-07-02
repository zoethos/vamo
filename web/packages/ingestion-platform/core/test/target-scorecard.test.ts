import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";

import {
  rankTargetCandidates,
  scoreTargetCandidate,
  type TargetCandidateInput
} from "../src/target-scorecard.js";

const fixture = JSON.parse(
  readFileSync("fixtures/platform/ip14/proposal-input.json", "utf8")
) as { candidates: TargetCandidateInput[] };

const [vamoTarget, missingAttribution, unsafeGoogle] = fixture.candidates;

describe("target selection scorecard", () => {
  it("ranks a valid Vamo target above invalid and unsafe options", () => {
    const ranked = rankTargetCandidates([unsafeGoogle, missingAttribution, vamoTarget]);

    assert.equal(ranked[0]?.targetId, "vamo-place-intelligence");
    assert.equal(ranked[0]?.eligibleForScheduling, true);

    // Both other options are blocked from scheduling.
    assert.equal(ranked[1]?.eligibleForScheduling, false);
    assert.equal(ranked[2]?.eligibleForScheduling, false);

    // The valid target outscores the unsafe one.
    const unsafe = ranked.find((card) => card.targetId === "google-live-rehearsal");
    assert.ok(ranked[0]!.score > unsafe!.score);
  });

  it("blocks scheduling when source attribution/rights are missing", () => {
    const card = scoreTargetCandidate(missingAttribution);

    assert.equal(card.eligibleForScheduling, false);
    assert.ok(card.blockingGates.includes("source_rights"));

    const sourceRights = card.criteria.find((criterion) => criterion.criterion === "source_rights");
    assert.equal(sourceRights?.gatePassed, false);
    assert.match(sourceRights?.reason ?? "", /attribution/i);
  });

  it("blocks live-only sources from seeding a durable cache", () => {
    const card = scoreTargetCandidate(unsafeGoogle);

    assert.equal(card.eligibleForScheduling, false);
    assert.ok(card.blockingGates.includes("source_rights"));
    const sourceRights = card.criteria.find((criterion) => criterion.criterion === "source_rights");
    assert.match(sourceRights?.reason ?? "", /live-only/i);
  });

  it("scores every criterion as a hard gate and is deterministic", () => {
    const first = scoreTargetCandidate(vamoTarget);
    const second = scoreTargetCandidate(vamoTarget);

    assert.deepEqual(first, second);
    assert.equal(first.criteria.length, 9);
    assert.ok(first.criteria.every((criterion) => criterion.hardGate));
    assert.ok(first.score > 0 && first.score <= 1);
  });
});

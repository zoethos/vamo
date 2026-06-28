import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";

import {
  buildScheduleProposal,
  type BuildScheduleProposalInput,
  type QuotaBudget,
  type RunWindow,
  type ScheduleScope,
  type StopConditions
} from "../src/schedule-proposal.js";
import { scoreTargetCandidate, type TargetCandidateInput } from "../src/target-scorecard.js";

interface Ip14Fixture {
  scope: ScheduleScope;
  batchSize: number;
  checkpointEveryRows: number;
  quotaBudget: QuotaBudget;
  runWindow: RunWindow;
  stopConditions: StopConditions;
  candidates: TargetCandidateInput[];
}

const fixture = JSON.parse(
  readFileSync("fixtures/platform/ip14/proposal-input.json", "utf8")
) as Ip14Fixture;

const [vamoTarget, , unsafeGoogle] = fixture.candidates;

function proposalInput(
  candidate: TargetCandidateInput,
  overrides: Partial<BuildScheduleProposalInput> = {}
): BuildScheduleProposalInput {
  return {
    scorecard: scoreTargetCandidate(candidate),
    tier: "sample_dry_run",
    safetyMode: candidate.safetyMode,
    scope: fixture.scope,
    batchSize: fixture.batchSize,
    checkpointEveryRows: fixture.checkpointEveryRows,
    quotaBudget: fixture.quotaBudget,
    runWindow: fixture.runWindow,
    stopConditions: fixture.stopConditions,
    forbidNonDryRun: true,
    ...overrides
  };
}

describe("schedule proposal policy", () => {
  it("emits a complete dry-run proposal for an eligible Vamo target", () => {
    const result = buildScheduleProposal(proposalInput(vamoTarget));

    assert.equal(result.ok, true);
    if (!result.ok) {
      return;
    }
    const proposal = result.proposal;
    assert.equal(proposal.projectKey, "vamo");
    assert.equal(proposal.targetId, "vamo-place-intelligence-staging");
    assert.equal(proposal.safetyMode, "dry_run");
    assert.equal(proposal.tier, "sample_dry_run");
    assert.equal(proposal.scope.rowLimit, 3);
    assert.ok(proposal.quotaBudget.maxRows > 0);
    assert.ok(proposal.stopConditions.honorOperatorPause);
    assert.equal(proposal.approval.required, true);
    assert.equal(proposal.approval.requireMfa, true);
    assert.equal(proposal.aiRationale.advisoryOnly, true);
    assert.equal(proposal.aiRationale.generator, "policy_advisory_placeholder");
    assert.ok(proposal.aiRationale.evidence.length > 0);
  });

  it("rejects production_write for IP-14", () => {
    const result = buildScheduleProposal(
      proposalInput(vamoTarget, { safetyMode: "production_write" })
    );

    assert.equal(result.ok, false);
    if (result.ok) {
      return;
    }
    assert.ok(result.errors.some((error) => error.code === "production_write_forbidden"));
  });

  it("keeps staging_write disabled for this slice", () => {
    const result = buildScheduleProposal(
      proposalInput(vamoTarget, { safetyMode: "staging_write" })
    );

    assert.equal(result.ok, false);
    if (result.ok) {
      return;
    }
    assert.ok(
      result.errors.some((error) => error.code === "staging_write_disabled_for_slice")
    );
  });

  it("refuses to schedule a target that fails selection gates", () => {
    const result = buildScheduleProposal(proposalInput(unsafeGoogle));

    assert.equal(result.ok, false);
    if (result.ok) {
      return;
    }
    assert.ok(result.errors.some((error) => error.code === "production_write_forbidden"));
    assert.ok(result.errors.some((error) => error.code === "target_not_eligible"));
  });

  it("is deterministic: identical input yields an identical proposal", () => {
    const a = buildScheduleProposal(proposalInput(vamoTarget));
    const b = buildScheduleProposal(proposalInput(vamoTarget));

    assert.deepEqual(a, b);
  });
});

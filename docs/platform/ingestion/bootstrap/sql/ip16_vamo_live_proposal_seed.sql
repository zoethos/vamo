-- IP-16 — First Vamo live proposal seed (Confluendo control-plane only).
--
-- NOTE (IP-15.2): this seed uses the legacy target key
-- `vamo-place-intelligence-staging`. Do not rewrite it; new proposals should
-- use the environment-neutral key `vamo-place-intelligence`.
--
-- Purpose: seed exactly one progressive-backlog row so the ingestion dashboard
-- shows LIVE control-plane data (instead of the bundled SAMPLE) for the reviewed
-- Vamo dry run. This is NOT a Vamo staging/production write and triggers no
-- provider call or scraping. The JSONB payloads below are derived deterministically
-- from the bundled IP-14/IP-16 dry-run fixtures.
--
-- Run as the DB OWNER (e.g. Supabase SQL Editor). confluendo_app stays read-only.
-- Idempotent: re-running upserts the same row (on conflict do update).

begin;

do $$
begin
  if not exists (select 1 from ingestion_platform.ingestion_projects where project_key = 'vamo') then
    raise exception 'Project project_key=''vamo'' not found. Run control_bootstrap_confluendo.sql first.';
  end if;
end $$;

insert into ingestion_platform.ingestion_schedule_proposals
  (project_id, target_key, source_key, work_status, tier, safety_mode, scorecard, proposal, run_report)
select
  p.id,
  'vamo-place-intelligence-staging',
  'fsq-os-places-sample',
  'review_required',
  'sample_dry_run',
  'dry_run',
  $vamo_scorecard${
  "targetId": "vamo-place-intelligence-staging",
  "projectKey": "vamo",
  "sourceId": "fsq-os-places-sample",
  "safetyMode": "dry_run",
  "score": 0.9396,
  "criteria": [
    {
      "criterion": "consumer_value",
      "score": 1,
      "weight": 0.2,
      "hardGate": true,
      "gatePassed": true,
      "reason": "Consumer owner named the use case and it reduces live provider calls."
    },
    {
      "criterion": "source_rights",
      "score": 1,
      "weight": 0.18,
      "hardGate": true,
      "gatePassed": true,
      "reason": "Source license, attribution, and retention checks pass."
    },
    {
      "criterion": "target_readiness",
      "score": 1,
      "weight": 0.16,
      "hardGate": true,
      "gatePassed": true,
      "reason": "Target schema, upsert keys, RLS posture, and staging environment are ready."
    },
    {
      "criterion": "data_quality",
      "score": 0.63,
      "weight": 0.12,
      "hardGate": true,
      "gatePassed": true,
      "reason": "Required fields, coordinates, and a non-empty sample pass quality gates."
    },
    {
      "criterion": "checkpointability",
      "score": 1,
      "weight": 0.08,
      "hardGate": true,
      "gatePassed": true,
      "reason": "Cursor strategy declared and resume is tested."
    },
    {
      "criterion": "cost_and_quota",
      "score": 1,
      "weight": 0.08,
      "hardGate": true,
      "gatePassed": true,
      "reason": "Row limit, stop conditions, and budget are declared and acceptable."
    },
    {
      "criterion": "collision_risk",
      "score": 0.8,
      "weight": 0.08,
      "hardGate": true,
      "gatePassed": true,
      "reason": "Collision policy is \"review\"."
    },
    {
      "criterion": "blast_radius",
      "score": 1,
      "weight": 0.06,
      "hardGate": true,
      "gatePassed": true,
      "reason": "Run is bounded and the first shipment is staging-only."
    },
    {
      "criterion": "observability",
      "score": 1,
      "weight": 0.04,
      "hardGate": true,
      "gatePassed": true,
      "reason": "Events, checkpoints, dead letters, and stats are all observable."
    }
  ],
  "eligibleForScheduling": true,
  "blockingGates": [],
  "rationale": "vamo-place-intelligence-staging scores 0.9396 and passes all selection gates; eligible for scheduling at dry_run."
}$vamo_scorecard$::jsonb,
  $vamo_proposal${
  "projectKey": "vamo",
  "targetId": "vamo-place-intelligence-staging",
  "sourceId": "fsq-os-places-sample",
  "tier": "sample_dry_run",
  "scope": {
    "geography": "rome-italy",
    "category": "poi",
    "rowLimit": 3,
    "sourcePartition": "fsq-os-places-sample"
  },
  "batchSize": 2,
  "checkpointEveryRows": 2,
  "quotaBudget": {
    "maxRows": 3,
    "maxSourceCalls": 1,
    "maxRuntimeSeconds": 30,
    "maxFailures": 1
  },
  "runWindow": {
    "earliestStart": "2026-06-28T00:00:00Z",
    "latestStop": "2026-06-28T23:59:59Z",
    "quietHours": "none"
  },
  "stopConditions": {
    "maxPolicyBlockRate": 0.5,
    "maxDeadLetterRate": 0.5,
    "maxCollisionRate": 0.2,
    "stopOnSchemaMismatch": true,
    "stopOnTargetWriteFailure": true,
    "honorOperatorPause": true
  },
  "safetyMode": "dry_run",
  "aiRationale": {
    "generator": "policy_advisory_placeholder",
    "recommendedTier": "sample_dry_run",
    "confidence": "high",
    "summary": "Advisory: vamo-place-intelligence-staging passes 9/9 gates (score 0.9396); recommend running at sample_dry_run.",
    "evidence": [
      "consumer_value: Consumer owner named the use case and it reduces live provider calls.",
      "source_rights: Source license, attribution, and retention checks pass.",
      "target_readiness: Target schema, upsert keys, RLS posture, and staging environment are ready.",
      "data_quality: Required fields, coordinates, and a non-empty sample pass quality gates.",
      "checkpointability: Cursor strategy declared and resume is tested.",
      "collision_risk: Collision policy is \"review\".",
      "cost_and_quota: Row limit, stop conditions, and budget are declared and acceptable.",
      "blast_radius: Run is bounded and the first shipment is staging-only.",
      "observability: Events, checkpoints, dead letters, and stats are all observable."
    ],
    "advisoryOnly": true
  },
  "approval": {
    "required": true,
    "role": "ingestion_admin",
    "requireMfa": true,
    "requireAuditReason": true,
    "description": "Admin (MFA + audit reason) must approve before promoting this dry run to a staging canary."
  }
}$vamo_proposal$::jsonb,
  $vamo_run_report${
  "projectKey": "vamo",
  "targetId": "vamo-place-intelligence-staging",
  "sourceId": "fsq-os-places-sample",
  "tier": "sample_dry_run",
  "safetyMode": "dry_run",
  "stages": [
    {
      "stage": "preflight",
      "status": "passed",
      "detail": "Preflight passed: specs, rights, attribution, schema, keys, RLS, dry-run posture.",
      "signal": "preflight_passed"
    },
    {
      "stage": "scout",
      "status": "passed",
      "detail": "Scouted 2 sample rows: 1 staged, 0 dead-lettered, 0 policy-blocked.",
      "signal": "scout_sampled"
    },
    {
      "stage": "sample_dry_run",
      "status": "passed",
      "detail": "Dry-run diff: 2 insert, 0 update, 0 no-op (no target writes).",
      "signal": "sample_dry_run_diff_ready"
    },
    {
      "stage": "review_required",
      "status": "review_required",
      "detail": "Dry run complete. Operator review required before any staging canary; no write occurred.",
      "signal": "review_required"
    }
  ],
  "currentStage": "review_required",
  "preflight": {
    "passed": true,
    "checks": [
      {
        "id": "spec_valid",
        "passed": true,
        "detail": "Pipeline and target specs parsed and validated by the spec kernel."
      },
      {
        "id": "source_rights",
        "passed": true,
        "detail": "Source license permits storing facts and is not live-only."
      },
      {
        "id": "attribution",
        "passed": true,
        "detail": "Source attribution is present and enforced by a quality gate."
      },
      {
        "id": "target_schema_ready",
        "passed": true,
        "detail": "Target declares at least one shipment table."
      },
      {
        "id": "upsert_keys",
        "passed": true,
        "detail": "Every target table declares upsert keys."
      },
      {
        "id": "rls_posture",
        "passed": true,
        "detail": "Target requires RLS on exposed schemas."
      },
      {
        "id": "dry_run_only",
        "passed": true,
        "detail": "Target write mode and default shipment mode are dry_run."
      },
      {
        "id": "selection_gates",
        "passed": true,
        "detail": "Target passes all selection scorecard gates."
      }
    ],
    "failures": []
  },
  "scout": {
    "sampleRowCount": 2,
    "candidateCount": 1,
    "deadLetterCount": 0,
    "policyBlockCount": 0,
    "detail": "Scouted 2 sample rows: 1 staged, 0 dead-lettered, 0 policy-blocked."
  },
  "rowCounts": {
    "read": 3,
    "staged": 1,
    "policyBlocked": 1,
    "deadLettered": 2
  },
  "shipmentDiff": {
    "compatible": true,
    "insert": 2,
    "update": 0,
    "noOp": 0,
    "delete": 0,
    "total": 2,
    "incompatibilities": 0
  },
  "checkpoint": {
    "cursorScope": "source_row_id",
    "cursorValue": 3,
    "lastRecordKey": "fsq_missing_name",
    "processedCount": 3
  },
  "policyBlocks": [
    "scope_mismatch: fsq_eiffel_tower outside rome-italy/poi"
  ],
  "deadLetters": [
    "missing_mapped_field: Required mapping source \"source.name\" is missing.",
    "missing_mapped_field: Required mapping source \"source.name\" is missing."
  ],
  "wroteToTarget": false,
  "reachedReview": true,
  "aiRationale": {
    "generator": "policy_advisory_placeholder",
    "recommendedTier": "sample_dry_run",
    "confidence": "high",
    "summary": "Advisory: vamo-place-intelligence-staging passes 9/9 gates (score 0.9396); recommend running at sample_dry_run.",
    "evidence": [
      "consumer_value: Consumer owner named the use case and it reduces live provider calls.",
      "source_rights: Source license, attribution, and retention checks pass.",
      "target_readiness: Target schema, upsert keys, RLS posture, and staging environment are ready.",
      "data_quality: Required fields, coordinates, and a non-empty sample pass quality gates.",
      "checkpointability: Cursor strategy declared and resume is tested.",
      "collision_risk: Collision policy is \"review\".",
      "cost_and_quota: Row limit, stop conditions, and budget are declared and acceptable.",
      "blast_radius: Run is bounded and the first shipment is staging-only.",
      "observability: Events, checkpoints, dead letters, and stats are all observable."
    ],
    "advisoryOnly": true
  },
  "nextApproval": {
    "required": true,
    "role": "ingestion_admin",
    "requireMfa": true,
    "requireAuditReason": true,
    "description": "Admin (MFA + audit reason) must approve before promoting this dry run to a staging canary."
  }
}$vamo_run_report$::jsonb
from ingestion_platform.ingestion_projects p
where p.project_key = 'vamo'
on conflict (project_id, target_key) do update set
  source_key  = excluded.source_key,
  work_status = excluded.work_status,
  tier        = excluded.tier,
  safety_mode = excluded.safety_mode,
  scorecard   = excluded.scorecard,
  proposal    = excluded.proposal,
  run_report  = excluded.run_report,
  updated_at  = now();

commit;

-- Optional verification (read-only):
-- select sp.target_key, sp.work_status, sp.safety_mode,
--        sp.run_report->>'wroteToTarget'             as wrote_to_target,
--        sp.run_report->>'reachedReview'             as reached_review,
--        sp.run_report->'shipmentDiff'->>'compatible' as diff_compatible
-- from ingestion_platform.ingestion_schedule_proposals sp
-- join ingestion_platform.ingestion_projects p on p.id = sp.project_id
-- where p.project_key = 'vamo' and sp.target_key = 'vamo-place-intelligence-staging';

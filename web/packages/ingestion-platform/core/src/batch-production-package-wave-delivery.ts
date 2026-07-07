/**
 * Batch production package-wave delivery (IP-18.6.3).
 *
 * Releases expired approvals, re-checks drift, delivers approved packages to the
 * consumer production inbox via the IP-17 adapter, and records control-plane
 * evidence. Never applies consumer product rows.
 */

import { Client, type QueryResult } from "pg";

import type { ProductionInboxDeliveryResult } from "../../adapters/target/src/postgres-production-inbox.js";
import { deliverPostgresProductionInboxPackage } from "../../adapters/target/src/postgres-production-inbox.js";
import type { TargetProjectSpec } from "../../spec/src/types.js";
import {
  buildBatchWaveUnitScope,
  filterCandidatesForWaveUnit,
  type BatchWaveUnitScope
} from "./batch-staging-canary-wave-candidates.js";
import { releaseExpiredProductionPackageWaves } from "./batch-production-package-wave-expiry-control.js";
import {
  evaluateBatchProductionPackageWaveDelivery,
  type BatchProductionPackageWaveDeliveryPlan
} from "./batch-production-package-wave-delivery-policy.js";
import { loadProductionPackageWave } from "./batch-production-package-wave-load.js";
import { buildBatchUnitProgressiveRunReport } from "./batch-production-package-wave-run-report.js";
import type { BatchQueueItem } from "./batch-queue-read-model.js";
import { loadBatchQueueSnapshot } from "./batch-queue-control-read.js";
import { loadProductionPackageWaveApprovalContext } from "./batch-production-package-wave-read.js";
import type { PipelineRunResult, StagedCandidate } from "./pipeline-runner.js";
import { buildProductionInboxPackage } from "./shipment-package.js";

const DEFAULT_WAVE_CANDIDATE_SCAN_BATCH_SIZE = 1000;

export interface BatchProductionPackageWaveDeliveryPgClientLike {
  query<T extends Record<string, unknown> = Record<string, unknown>>(
    sql: string,
    values?: unknown[]
  ): Promise<QueryResult<T>>;
}

export interface BatchProductionPackageWaveDeliveryDeps {
  loadCandidates?: (input: {
    unit: BatchQueueItem;
    scope: BatchWaveUnitScope;
  }) => Promise<StagedCandidate[]>;
  deliverPackage?: typeof deliverPostgresProductionInboxPackage;
}

export interface ExecuteBatchProductionPackageWaveInput {
  controlConnectionString?: string;
  productionInboxConnectionString?: string;
  controlClient?: BatchProductionPackageWaveDeliveryPgClientLike;
  projectKey: string;
  targetEnvironment: string;
  waveKey?: string;
  approvalAuditId?: string;
  maxUnits?: number;
  maxRows?: number;
  maxPackages?: number;
  execute: boolean;
  actor: { type: "operator" | "api"; id: string };
  reason: string;
  proveProduction: () => boolean | Promise<boolean>;
  deps?: BatchProductionPackageWaveDeliveryDeps;
  now?: string;
}

export interface ExecuteBatchProductionPackageWaveUnitResult {
  unitKey: string;
  packageId: string;
  packageKey: string;
  checksum: string;
  itemCount: number;
  status: "delivered" | "skipped" | "blocked";
  idempotentReplay: boolean;
  blockCode?: string;
  blockMessage?: string;
}

export interface ExecuteBatchProductionPackageWaveResult {
  ok: true;
  previewOnly: boolean;
  waveId: string;
  waveKey: string;
  waveStatus: string;
  deliveryAuditId: string | null;
  idempotentReplay: boolean;
  deliveredCount: number;
  skippedCount: number;
  blockedCount: number;
  unitResults: ExecuteBatchProductionPackageWaveUnitResult[];
  safetySummary: string[];
  plan: BatchProductionPackageWaveDeliveryPlan;
}

interface LedgerFailureEvidence {
  waveId: string;
  waveKey: string;
  unitKey: string;
  packageId: string;
  packageKey: string;
  checksum: string;
  itemCount: number;
  wroteToInbox: boolean;
  idempotent: boolean;
}

export async function executeBatchProductionPackageWave(
  input: ExecuteBatchProductionPackageWaveInput
): Promise<ExecuteBatchProductionPackageWaveResult> {
  const { client: controlClient, ownedClient } = await openControlClient(
    input.controlClient,
    input.controlConnectionString
  );
  try {
    const now = input.now ?? new Date().toISOString();
    const deliverPackage = input.deps?.deliverPackage ?? deliverPostgresProductionInboxPackage;

    if (input.execute) {
      await releaseExpiredProductionPackageWaves({
        client: controlClient,
        projectKey: input.projectKey,
        actor: input.actor,
        now
      });
    }

    const wave = await loadProductionPackageWave({
      client: controlClient,
      projectKey: input.projectKey,
      waveKey: input.waveKey,
      approvalAuditId: input.approvalAuditId
    });

    const snapshot = await loadBatchQueueSnapshot({
      client: controlClient,
      projectKey: input.projectKey,
      targetKey: wave?.targetKey
    });
    const queueItemsByUnitKey = Object.fromEntries(
      (snapshot?.items ?? []).map((item) => [item.unitKey, item])
    ) as Record<string, BatchQueueItem>;

    const approvalContext = wave
      ? await loadProductionPackageWaveApprovalContext({
          client: controlClient,
          projectKey: input.projectKey,
          targetKey: wave.targetKey
        })
      : { stagingEvidenceByUnitKey: {}, occupiedUnitKeys: new Set(), hasPriorDeliveredPackage: false };

    const decision = evaluateBatchProductionPackageWaveDelivery({
      projectKey: input.projectKey,
      targetEnvironment: input.targetEnvironment,
      wave,
      queueItemsByUnitKey,
      stagingEvidenceByUnitKey: approvalContext.stagingEvidenceByUnitKey,
      maxUnits: input.maxUnits,
      maxRows: input.maxRows,
      maxPackages: input.maxPackages,
      now
    });

    if (!decision.ok) {
      const message = decision.blocks.map((block) => block.message).join("; ");
      throw new Error(`Production package-wave delivery blocked: ${message}`);
    }

    const plan = decision.plan;

    if (!input.execute) {
      return {
        ok: true,
        previewOnly: true,
        waveId: plan.waveId,
        waveKey: plan.waveKey,
        waveStatus: wave?.status ?? "unknown",
        deliveryAuditId: wave?.deliveryAuditId ?? null,
        idempotentReplay: false,
        deliveredCount: 0,
        skippedCount: plan.unitPlans.filter((unit) => unit.status === "skip_delivered").length,
        blockedCount: 0,
        unitResults: [],
        safetySummary: plan.safetySummary,
        plan
      };
    }

    if (!input.productionInboxConnectionString?.trim()) {
      throw new Error("VAMO_PRODUCTION_INBOX_DATABASE_URL is required for production package-wave delivery.");
    }

    const unitResults: ExecuteBatchProductionPackageWaveUnitResult[] = [];
    let deliveredCount = 0;
    let skippedCount = 0;
    let blockedCount = 0;
    let idempotentReplay = true;
    let deliveryAuditId: string | null = wave?.deliveryAuditId ?? null;
    let stop = false;

  for (const unitPlan of plan.unitPlans) {
    if (unitPlan.status === "skip_delivered") {
      unitResults.push({
        unitKey: unitPlan.unitKey,
        packageId: unitPlan.storedPackageId ?? unitPlan.packageKey,
        packageKey: unitPlan.packageKey,
        checksum: unitPlan.storedChecksum ?? "",
        itemCount: 0,
        status: "skipped",
        idempotentReplay: true
      });
      skippedCount += 1;
      continue;
    }
    if (stop || unitPlan.status !== "pending") {
      continue;
    }

    const queueItem = queueItemsByUnitKey[unitPlan.unitKey];
    if (!queueItem) {
      unitResults.push({
        unitKey: unitPlan.unitKey,
        packageId: unitPlan.packageKey,
        packageKey: unitPlan.packageKey,
        checksum: "",
        itemCount: 0,
        status: "blocked",
        idempotentReplay: false,
        blockCode: "queue_status_drift",
        blockMessage: `Queue item "${unitPlan.unitKey}" is missing at delivery time.`
      });
      blockedCount += 1;
      stop = true;
      continue;
    }

    const waveItem = wave!.items.find((item) => item.id === unitPlan.waveItemId);
    if (!waveItem) {
      throw new Error(`Wave item ${unitPlan.waveItemId} disappeared during delivery.`);
    }

    const scope = buildBatchWaveUnitScope(queueItem);
    if (!scope) {
      unitResults.push({
        unitKey: unitPlan.unitKey,
        packageId: unitPlan.packageKey,
        packageKey: unitPlan.packageKey,
        checksum: "",
        itemCount: 0,
        status: "blocked",
        idempotentReplay: false,
        blockCode: "dry_run_evidence_drift",
        blockMessage: `Unit "${unitPlan.unitKey}" no longer has valid dry-run scope.`
      });
      blockedCount += 1;
      stop = true;
      continue;
    }

    const candidates = input.deps?.loadCandidates
      ? await input.deps.loadCandidates({ unit: queueItem, scope })
      : [];

    if (candidates.length === 0) {
      unitResults.push({
        unitKey: unitPlan.unitKey,
        packageId: unitPlan.packageKey,
        packageKey: unitPlan.packageKey,
        checksum: "",
        itemCount: 0,
        status: "blocked",
        idempotentReplay: false,
        blockCode: "dry_run_evidence_drift",
        blockMessage: `No deliverable candidates were resolved for unit "${unitPlan.unitKey}".`
      });
      blockedCount += 1;
      stop = true;
      continue;
    }

    const approvedBy =
      typeof wave!.approvedBy?.email === "string" ? wave!.approvedBy.email : input.actor.id;
    const pkg = buildProductionInboxPackage({
      packageId: unitPlan.packageKey,
      consumerKey: input.projectKey,
      runReport: buildBatchUnitProgressiveRunReport({
        projectKey: input.projectKey,
        targetKey: plan.targetKey,
        sourceKey: queueItem.sourceKey,
        dryRunEvidence: waveItem.dryRunEvidence
      }),
      candidates,
      approvedBy,
      approvalReason: wave!.auditReason
    });

    const delivered = await deliverPackage({
      connectionString: input.productionInboxConnectionString,
      package: pkg,
      proveProduction: input.proveProduction
    });

    if (!delivered.ok) {
      unitResults.push({
        unitKey: unitPlan.unitKey,
        packageId: unitPlan.packageKey,
        packageKey: unitPlan.packageKey,
        checksum: "",
        itemCount: 0,
        status: "blocked",
        idempotentReplay: false,
        blockCode: delivered.code,
        blockMessage: delivered.message
      });
      blockedCount += 1;
      stop = true;
      continue;
    }

    if (
      unitPlan.storedChecksum &&
      unitPlan.storedChecksum !== delivered.checksum &&
      !delivered.idempotent
    ) {
      throw new Error(
        `Checksum mismatch for ${unitPlan.packageKey}: stored ${unitPlan.storedChecksum}, incoming ${delivered.checksum}.`
      );
    }

    try {
      const ledger = await recordPackageWaveUnitDelivery(controlClient, {
        waveId: plan.waveId,
        waveItemId: unitPlan.waveItemId,
        batchPlanId: wave!.batchPlanId,
        unitKey: unitPlan.unitKey,
        packageId: delivered.packageId,
        packageKey: unitPlan.packageKey,
        checksum: delivered.checksum,
        itemCount: delivered.itemCount,
        actor: input.actor,
        reason: input.reason,
        approvalAuditId: plan.approvalAuditId,
        now,
        delivered
      });
      deliveryAuditId = ledger.deliveryAuditId ?? deliveryAuditId;
    } catch (error) {
      const evidence: LedgerFailureEvidence = {
        waveId: plan.waveId,
        waveKey: plan.waveKey,
        unitKey: unitPlan.unitKey,
        packageId: delivered.packageId,
        packageKey: unitPlan.packageKey,
        checksum: delivered.checksum,
        itemCount: delivered.itemCount,
        wroteToInbox: delivered.wroteToInbox,
        idempotent: delivered.idempotent
      };
      throw new Error(
        `CONTROL LEDGER UPDATE FAILED AFTER PRODUCTION INBOX DELIVERY. Recovery evidence: ${JSON.stringify(evidence)}. Original error: ${
          error instanceof Error ? error.message : String(error)
        }`
      );
    }

    unitResults.push({
      unitKey: unitPlan.unitKey,
      packageId: delivered.packageId,
      packageKey: unitPlan.packageKey,
      checksum: delivered.checksum,
      itemCount: delivered.itemCount,
      status: "delivered",
      idempotentReplay: delivered.idempotent
    });
    deliveredCount += delivered.idempotent ? 0 : 1;
    if (!delivered.idempotent) {
      idempotentReplay = false;
    } else {
      skippedCount += 1;
    }
  }

  const waveStatus = blockedCount > 0 ? "blocked" : deliveredCount > 0 || skippedCount > 0 ? "delivered" : wave?.status ?? "approved";

    return {
      ok: true,
      previewOnly: false,
      waveId: plan.waveId,
      waveKey: plan.waveKey,
      waveStatus,
      deliveryAuditId,
      idempotentReplay,
      deliveredCount,
      skippedCount,
      blockedCount,
      unitResults,
      safetySummary: plan.safetySummary,
      plan
    };
  } finally {
    if (ownedClient) {
      await ownedClient.end();
    }
  }
}

async function recordPackageWaveUnitDelivery(
  client: BatchProductionPackageWaveDeliveryPgClientLike,
  input: {
    waveId: string;
    waveItemId: string;
    batchPlanId: string;
    unitKey: string;
    packageId: string;
    packageKey: string;
    checksum: string;
    itemCount: number;
    actor: { type: "operator" | "api"; id: string };
    reason: string;
    approvalAuditId: string | null;
    now: string;
    delivered: ProductionInboxDeliveryResult & { ok: true };
  }
): Promise<{ deliveryAuditId: string | null }> {
  await client.query("begin");
  await client.query("set local statement_timeout = '15s'");

  try {
    const audit = await client.query<{ id: string }>(
      `
        insert into ingestion_platform.ingestion_audit_log (
          project_id,
          actor_type,
          actor_id,
          action,
          target_type,
          target_id,
          reason,
          payload,
          created_at
        )
        select
          bp.project_id,
          $2,
          $3,
          'deliver_batch_production_package_wave',
          'batch_production_package_wave',
          w.id::text,
          $4,
          $5::jsonb,
          $6::timestamptz
        from ingestion_platform.ingestion_batch_production_package_waves w
        join ingestion_platform.ingestion_batch_plans bp on bp.id = w.batch_plan_id
        where w.id = $1::bigint
        returning id::text as id
      `,
      [
        input.waveId,
        input.actor.type,
        input.actor.id,
        input.reason,
        JSON.stringify({
          unitKey: input.unitKey,
          packageId: input.packageId,
          packageKey: input.packageKey,
          checksum: input.checksum,
          itemCount: input.itemCount,
          approvalAuditId: input.approvalAuditId,
          idempotent: input.delivered.idempotent,
          wroteToInbox: input.delivered.wroteToInbox
        }),
        input.now
      ]
    );
    const deliveryAuditId = audit.rows[0]?.id ?? null;

    await client.query(
      `
        update ingestion_platform.ingestion_batch_production_package_wave_items
        set status = 'delivered',
            package_id = $2,
            package_key = $3,
            checksum = $4,
            updated_at = $5::timestamptz
        where id = $1::bigint
      `,
      [input.waveItemId, input.packageId, input.packageKey, input.checksum, input.now]
    );

    await client.query(
      `
        update ingestion_platform.ingestion_batch_queue_items
        set status = 'production_package_delivered',
            updated_at = $3::timestamptz
        where batch_plan_id = $1::bigint
          and unit_key = $2
          and status in ('production_package_approved', 'production_package_delivering', 'production_package_delivered')
      `,
      [input.batchPlanId, input.unitKey, input.now]
    );

    await client.query(
      `
        update ingestion_platform.ingestion_batch_production_package_waves
        set status = case when status = 'blocked' then status else 'delivered' end,
            package_id = coalesce(package_id, $2),
            package_key = coalesce(package_key, $3),
            package_checksum = coalesce(package_checksum, $4),
            delivery_audit_id = coalesce(delivery_audit_id, $5),
            delivery_status = 'production_inbox_delivered',
            consumer_apply_status = 'pending',
            summary = coalesce(summary, '{}'::jsonb) || $6::jsonb,
            updated_at = $7::timestamptz
        where id = $1::bigint
      `,
      [
        input.waveId,
        input.packageId,
        input.packageKey,
        input.checksum,
        deliveryAuditId,
        JSON.stringify({
          lastDeliveredUnitKey: input.unitKey,
          itemCount: input.itemCount
        }),
        input.now
      ]
    );

    await client.query("commit");
    return { deliveryAuditId };
  } catch (error) {
    await client.query("rollback");
    throw error;
  }
}

async function openControlClient(
  client?: BatchProductionPackageWaveDeliveryPgClientLike,
  connectionString?: string
): Promise<{ client: BatchProductionPackageWaveDeliveryPgClientLike; ownedClient?: Client }> {
  if (client) {
    return { client };
  }
  if (!connectionString?.trim()) {
    throw new Error("INGESTION_CONTROL_DATABASE_URL is required for production package-wave delivery.");
  }
  const ownedClient = new Client({ connectionString });
  await ownedClient.connect();
  return { client: ownedClient, ownedClient };
}

export async function defaultLoadProductionPackageWaveCandidates(input: {
  unit: BatchQueueItem;
  scope: BatchWaveUnitScope;
  pipeline: import("../../spec/src/types.js").PipelineSpec;
  fixtureRoot: string;
  runPipeline: (input: {
    pipeline: import("../../spec/src/types.js").PipelineSpec;
    batchSize: number;
    fixtureRoot: string;
  }) => Promise<PipelineRunResult>;
}): Promise<StagedCandidate[]> {
  const run = await input.runPipeline({
    pipeline: input.pipeline,
    batchSize: Math.max(input.scope.maxRows, DEFAULT_WAVE_CANDIDATE_SCAN_BATCH_SIZE),
    fixtureRoot: input.fixtureRoot
  });
  return filterCandidatesForWaveUnit(run.candidates, input.scope);
}

export type { TargetProjectSpec };

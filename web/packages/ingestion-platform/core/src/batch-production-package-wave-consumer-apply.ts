/**
 * Production package-wave consumer apply orchestration (IP-18.6.6).
 *
 * Invokes the Vamo-owned apply boundary, records control-plane audit evidence,
 * and refreshes read-only apply telemetry.
 */

import { Client, type QueryResult } from "pg";

import {
  applyPostgresProductionInboxPackage,
  readPostgresProductionInboxApplyPreflight,
  type ProductionInboxApplyPreflight,
  type ProductionInboxApplyResultPayload
} from "../../adapters/target/src/postgres-production-inbox-apply.js";
import type { BatchControlActor } from "./batch-control-actor.js";
import { refreshProductionPackageApplyTelemetry } from "./batch-production-package-wave-apply-telemetry.js";
import {
  evaluateProductionPackageConsumerApply,
  type ProductionPackageConsumerApplyBlock
} from "./batch-production-package-wave-consumer-apply-policy.js";
import { loadBatchQueueSnapshot } from "./batch-queue-control-read.js";
import type { AdminPrincipal } from "./admin-auth.js";
import type { BatchQueueSnapshot } from "./batch-queue-read-model.js";

export interface ProductionPackageConsumerApplyPgClientLike {
  query<T extends Record<string, unknown> = Record<string, unknown>>(
    sql: string,
    values?: unknown[]
  ): Promise<QueryResult<T>>;
}

export interface ExecuteProductionPackageConsumerApplyInput {
  projectKey: string;
  packageId: string;
  auditReason: string;
  principal: AdminPrincipal;
  actor: BatchControlActor;
  controlConnectionString?: string;
  applyConnectionString?: string;
  telemetryConnectionString?: string;
  proveApply?: () => boolean | Promise<boolean>;
  proveTelemetry?: () => boolean | Promise<boolean>;
  now?: string;
}

export type ExecuteProductionPackageConsumerApplyResult =
  | {
      ok: true;
      packageId: string;
      applyResult: ProductionInboxApplyResultPayload;
      auditId: string;
      preflight: ProductionInboxApplyPreflight;
      snapshot?: BatchQueueSnapshot;
      idempotentReplay: boolean;
    }
  | {
      ok: false;
      blocks?: ProductionPackageConsumerApplyBlock[];
      applyResult?: ProductionInboxApplyResultPayload;
      preflight?: ProductionInboxApplyPreflight;
      applyLog?: { result: string | null; detail: string | null };
      itemErrors?: Array<{ itemKey: string; applyError: string | null }>;
      message?: string;
    };

interface WaveContextRow extends Record<string, unknown> {
  waveId: string;
}

interface AuditRow extends Record<string, unknown> {
  id: string;
}

export async function loadProductionPackageConsumerApplyPreflight(input: {
  packageId: string;
  applyConnectionString?: string;
  proveApply?: () => boolean | Promise<boolean>;
}): Promise<
  | { ok: true; preflight: ProductionInboxApplyPreflight }
  | { ok: false; code: string; message: string }
> {
  const applyConnectionString = input.applyConnectionString?.trim();
  if (!applyConnectionString) {
    return {
      ok: false,
      code: "apply_not_configured",
      message: "VAMO_PRODUCTION_INBOX_APPLY_DATABASE_URL is not configured."
    };
  }

  const preflight = await readPostgresProductionInboxApplyPreflight({
    packageId: input.packageId,
    connectionString: applyConnectionString,
    proveApply: input.proveApply
  });
  if (!preflight.ok) {
    return { ok: false, code: preflight.code, message: preflight.message };
  }
  return { ok: true, preflight: preflight.preflight };
}

export async function executeProductionPackageConsumerApply(
  input: ExecuteProductionPackageConsumerApplyInput
): Promise<ExecuteProductionPackageConsumerApplyResult> {
  const applyConnectionString = input.applyConnectionString?.trim();
  const controlConnectionString = input.controlConnectionString?.trim();
  const now = input.now ?? new Date().toISOString();

  const preflightLoaded = applyConnectionString
    ? await loadProductionPackageConsumerApplyPreflight({
        packageId: input.packageId,
        applyConnectionString,
        proveApply: input.proveApply
      })
    : { ok: false as const, code: "apply_not_configured", message: "Apply database URL is not configured." };

  const decision = evaluateProductionPackageConsumerApply({
    projectKey: input.projectKey,
    packageId: input.packageId,
    auditReason: input.auditReason,
    principal: input.principal,
    preflight: preflightLoaded.ok ? preflightLoaded.preflight : null,
    applyDatabaseConfigured: Boolean(applyConnectionString),
    now
  });

  if (!decision.ok) {
    return {
      ok: false,
      blocks: decision.blocks,
      preflight: preflightLoaded.ok ? preflightLoaded.preflight : undefined
    };
  }

  if (!applyConnectionString || !preflightLoaded.ok) {
    return {
      ok: false,
      blocks: [
        {
          code: "apply_not_configured",
          message: "VAMO_PRODUCTION_INBOX_APPLY_DATABASE_URL is not configured."
        }
      ]
    };
  }

  const applied = await applyPostgresProductionInboxPackage({
    packageId: input.packageId,
    approvedBy: input.principal.email,
    approvalReason: input.auditReason,
    connectionString: applyConnectionString,
    proveApply: input.proveApply
  });

  if (!applied.ok) {
    const failureEvidence = await readPostgresProductionInboxApplyPreflight({
      packageId: input.packageId,
      connectionString: applyConnectionString,
      proveApply: input.proveApply
    });
    const preflight = failureEvidence.ok ? failureEvidence.preflight : preflightLoaded.preflight;
    if (controlConnectionString) {
      await recordConsumerApplyAudit({
        connectionString: controlConnectionString,
        projectKey: input.projectKey,
        packageId: input.packageId,
        actor: input.actor,
        reason: input.auditReason,
        action: "apply_batch_production_package_wave_failed",
        payload: {
          packageId: input.packageId,
          applyResult: applied.result ?? null,
          applyLog: {
            result: preflight.latestApplyLogResult,
            detail: preflight.latestApplyLogDetail
          },
          itemErrors: preflight.items
            .filter((item) => item.applyError)
            .map((item) => ({ itemKey: item.itemKey, applyError: item.applyError }))
        },
        now
      });
    }
    return {
      ok: false,
      message: applied.message,
      applyResult: applied.result,
      preflight,
      applyLog: {
        result: preflight.latestApplyLogResult,
        detail: preflight.latestApplyLogDetail
      },
      itemErrors: preflight.items
        .filter((item) => item.applyError)
        .map((item) => ({ itemKey: item.itemKey, applyError: item.applyError }))
    };
  }

  let auditId = "0";
  if (controlConnectionString) {
    auditId = await recordConsumerApplyAudit({
      connectionString: controlConnectionString,
      projectKey: input.projectKey,
      packageId: input.packageId,
      actor: input.actor,
      reason: input.auditReason,
      action: "apply_batch_production_package_wave",
      payload: {
        packageId: input.packageId,
        applyResult: applied.result,
        approvedBy: input.principal.email
      },
      now
    });
  }

  let snapshot: BatchQueueSnapshot | undefined;
  if (controlConnectionString) {
    const loaded = await loadBatchQueueSnapshot({
      connectionString: controlConnectionString,
      projectKey: input.projectKey
    });
    if (loaded) {
      const telemetryDb = input.telemetryConnectionString?.trim();
      if (telemetryDb) {
        const refreshed = await refreshProductionPackageApplyTelemetry({
          snapshot: loaded,
          controlConnectionString,
          telemetryConnectionString: telemetryDb,
          proveTelemetry: input.proveTelemetry,
          syncControl: true,
          now
        });
        snapshot = refreshed.snapshot;
      } else {
        snapshot = loaded;
      }
    }
  }

  return {
    ok: true,
    packageId: input.packageId,
    applyResult: applied.result,
    auditId,
    preflight: preflightLoaded.preflight,
    snapshot,
    idempotentReplay: applied.result.skipped > 0 && applied.result.applied === 0
  };
}

async function recordConsumerApplyAudit(input: {
  connectionString: string;
  projectKey: string;
  packageId: string;
  actor: BatchControlActor;
  reason: string;
  action: string;
  payload: Record<string, unknown>;
  now: string;
}): Promise<string> {
  return withConsumerApplyClient(input.connectionString, async (client) => {
    const wave = await client.query<WaveContextRow>(
      `
        select w.id::text as "waveId"
        from ingestion_platform.ingestion_batch_production_package_wave_items wi
        join ingestion_platform.ingestion_batch_production_package_waves w on w.id = wi.wave_id
        join ingestion_platform.ingestion_batch_plans bp on bp.id = w.batch_plan_id
        join ingestion_platform.ingestion_projects p on p.id = bp.project_id
        where wi.package_id = $1
          and p.project_key = $2
        order by w.id desc
        limit 1
      `,
      [input.packageId, input.projectKey]
    );
    const waveId = wave.rows[0]?.waveId ?? input.packageId;

    const inserted = await client.query<AuditRow>(
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
        p.id,
        $2,
        $3,
        $4,
        'batch_production_package_wave',
        $5,
        $6,
        $7::jsonb,
        $8::timestamptz
      from ingestion_platform.ingestion_projects p
      where p.project_key = $1
      returning id::text as id
      `,
      [
        input.projectKey,
        input.actor.type,
        input.actor.id,
        input.action,
        waveId,
        input.reason,
        JSON.stringify(input.payload),
        input.now
      ]
    );
    return inserted.rows[0]?.id ?? "0";
  });
}

async function withConsumerApplyClient<T>(
  connectionString: string,
  run: (client: ProductionPackageConsumerApplyPgClientLike) => Promise<T>
): Promise<T> {
  const client = new Client({ connectionString });
  await client.connect();
  try {
    return await run(client);
  } finally {
    await client.end();
  }
}

/**
 * Production package-wave batch consumer apply orchestration (IP-18.8.4).
 */

import type { ProductionInboxApplyResultPayload } from "../../adapters/target/src/postgres-production-inbox-apply.js";
import type { BatchControlActor } from "./batch-control-actor.js";
import {
  evaluateProductionPackageWaveBatchApply,
  summarizeProductionPackageWaveBatchApplyPreflight,
  type ProductionPackageWaveBatchApplyBlock,
  type ProductionPackageWaveBatchApplyTarget
} from "./batch-production-package-wave-consumer-apply-batch-policy.js";
import {
  executeProductionPackageConsumerApply,
  loadProductionPackageConsumerApplyPreflight
} from "./batch-production-package-wave-consumer-apply.js";
import { loadProductionPackageWave } from "./batch-production-package-wave-load.js";
import type { AdminPrincipal } from "./admin-auth.js";

export interface ExecuteProductionPackageWaveConsumerApplyBatchInput {
  projectKey: string;
  waveKey: string;
  auditReason: string;
  principal: AdminPrincipal;
  actor: BatchControlActor;
  packageIds?: string[];
  unitKeys?: string[];
  controlConnectionString?: string;
  applyConnectionString?: string;
  telemetryConnectionString?: string;
  proveApply?: () => boolean | Promise<boolean>;
  proveTelemetry?: () => boolean | Promise<boolean>;
  now?: string;
}

export type ExecuteProductionPackageWaveConsumerApplyBatchResult =
  | {
      ok: true;
      waveKey: string;
      appliedPackageIds: string[];
      skippedAppliedPackageIds: string[];
      auditIds: string[];
      applyResults: ProductionInboxApplyResultPayload[];
      preflightSummary: ReturnType<typeof summarizeProductionPackageWaveBatchApplyPreflight>;
    }
  | {
      ok: false;
      blocks?: ProductionPackageWaveBatchApplyBlock[];
      failedPackageId?: string;
      applyResult?: ProductionInboxApplyResultPayload;
      message?: string;
    };

export async function loadProductionPackageWaveConsumerApplyBatchPreflight(input: {
  projectKey: string;
  waveKey: string;
  packageIds?: string[];
  unitKeys?: string[];
  controlConnectionString?: string;
  applyConnectionString?: string;
  proveApply?: () => boolean | Promise<boolean>;
}): Promise<
  | {
      ok: true;
      waveKey: string;
      targets: ProductionPackageWaveBatchApplyTarget[];
      skippedAppliedPackageIds: string[];
      preflightSummary: ReturnType<typeof summarizeProductionPackageWaveBatchApplyPreflight>;
    }
  | { ok: false; blocks: ProductionPackageWaveBatchApplyBlock[] }
> {
  const controlConnectionString = input.controlConnectionString?.trim();
  const applyConnectionString = input.applyConnectionString?.trim();
  if (!controlConnectionString || !applyConnectionString) {
    return {
      ok: false,
      blocks: [
        {
          code: "apply_not_configured",
          message: "Production inbox apply database URL is not configured."
        }
      ]
    };
  }

  const loaded = await loadProductionPackageWave({
    connectionString: controlConnectionString,
    projectKey: input.projectKey,
    waveKey: input.waveKey
  });
  if (!loaded) {
    return {
      ok: false,
      blocks: [
        {
          code: "wave_not_found",
          message: `Production package wave "${input.waveKey}" was not found.`
        }
      ]
    };
  }

  const prefetchesByPackageId: Record<string, ProductionPackageWaveBatchApplyTarget["preflight"]> =
    {};
  for (const item of loaded.items) {
    if (!item.packageId) {
      continue;
    }
    const preflightLoaded = await loadProductionPackageConsumerApplyPreflight({
      packageId: item.packageId,
      applyConnectionString,
      proveApply: input.proveApply
    });
    if (preflightLoaded.ok) {
      prefetchesByPackageId[item.packageId] = preflightLoaded.preflight;
    }
  }

  const resolved = evaluateProductionPackageWaveBatchApply({
    projectKey: input.projectKey,
    waveKey: loaded.waveKey,
    auditReason: "preflight",
    principal: {
      provider: "supabase",
      userId: "preflight",
      email: "preflight@example.com",
      role: "admin",
      scopes: [input.projectKey],
      assuranceLevel: "aal2",
      mfaRequired: false,
      hasVerifiedMfaFactor: true,
      stepUpSatisfiedAt: new Date().toISOString()
    },
    wave: mapLoadedWaveForBatchApply(loaded),
    packageIds: input.packageIds,
    unitKeys: input.unitKeys,
    prefetchesByPackageId,
    applyDatabaseConfigured: true
  });

  if (!resolved.ok) {
    return { ok: false, blocks: resolved.blocks };
  }

  return {
    ok: true,
    waveKey: loaded.waveKey,
    targets: resolved.targets,
    skippedAppliedPackageIds: resolved.skippedAppliedPackageIds,
    preflightSummary: summarizeProductionPackageWaveBatchApplyPreflight(
      resolved.targets,
      resolved.skippedAppliedPackageIds
    )
  };
}

export async function executeProductionPackageWaveConsumerApplyBatch(
  input: ExecuteProductionPackageWaveConsumerApplyBatchInput
): Promise<ExecuteProductionPackageWaveConsumerApplyBatchResult> {
  const controlConnectionString = input.controlConnectionString?.trim();
  const applyConnectionString = input.applyConnectionString?.trim();
  if (!controlConnectionString || !applyConnectionString) {
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

  const loaded = await loadProductionPackageWave({
    connectionString: controlConnectionString,
    projectKey: input.projectKey,
    waveKey: input.waveKey
  });
  if (!loaded) {
    return {
      ok: false,
      blocks: [
        {
          code: "wave_not_found",
          message: `Production package wave "${input.waveKey}" was not found.`
        }
      ]
    };
  }

  const prefetchesByPackageId: Record<string, ProductionPackageWaveBatchApplyTarget["preflight"]> =
    {};
  for (const item of loaded.items) {
    if (!item.packageId) {
      continue;
    }
    const preflightLoaded = await loadProductionPackageConsumerApplyPreflight({
      packageId: item.packageId,
      applyConnectionString,
      proveApply: input.proveApply
    });
    if (preflightLoaded.ok) {
      prefetchesByPackageId[item.packageId] = preflightLoaded.preflight;
    }
  }

  const decision = evaluateProductionPackageWaveBatchApply({
    projectKey: input.projectKey,
    waveKey: loaded.waveKey,
    auditReason: input.auditReason,
    principal: input.principal,
    wave: mapLoadedWaveForBatchApply(loaded),
    packageIds: input.packageIds,
    unitKeys: input.unitKeys,
    prefetchesByPackageId,
    applyDatabaseConfigured: true,
    now: input.now
  });

  if (!decision.ok) {
    return { ok: false, blocks: decision.blocks };
  }

  const appliedPackageIds: string[] = [];
  const auditIds: string[] = [];
  const applyResults: ProductionInboxApplyResultPayload[] = [];

  for (const target of decision.targets) {
    const result = await executeProductionPackageConsumerApply({
      projectKey: input.projectKey,
      packageId: target.packageId,
      auditReason: input.auditReason,
      principal: input.principal,
      actor: input.actor,
      controlConnectionString,
      applyConnectionString,
      telemetryConnectionString: input.telemetryConnectionString,
      proveApply: input.proveApply,
      proveTelemetry: input.proveTelemetry,
      now: input.now
    });

    if (!result.ok) {
      return {
        ok: false,
        blocks: result.blocks,
        failedPackageId: target.packageId,
        applyResult: result.applyResult,
        message: result.message
      };
    }

    appliedPackageIds.push(target.packageId);
    auditIds.push(result.auditId);
    applyResults.push(result.applyResult);
  }

  return {
    ok: true,
    waveKey: loaded.waveKey,
    appliedPackageIds,
    skippedAppliedPackageIds: decision.skippedAppliedPackageIds,
    auditIds,
    applyResults,
    preflightSummary: summarizeProductionPackageWaveBatchApplyPreflight(
      decision.targets,
      decision.skippedAppliedPackageIds
    )
  };
}

function mapLoadedWaveForBatchApply(
  loaded: NonNullable<Awaited<ReturnType<typeof loadProductionPackageWave>>>
) {
  return {
    waveKey: loaded.waveKey,
    status: loaded.status,
    items: loaded.items.map((item) => ({
      unitKey: item.unitKey,
      packageId: item.packageId,
      status: item.status,
      consumerApplyStatus: mapConsumerApplyStatus(item.status)
    }))
  };
}

function mapConsumerApplyStatus(status: string): string | null {
  if (status === "consumer_applied") {
    return "applied";
  }
  if (status === "consumer_apply_failed") {
    return "failed";
  }
  if (status === "consumer_apply_pending") {
    return "pending";
  }
  if (status === "production_package_delivered" || status === "delivered") {
    return "pending";
  }
  return null;
}

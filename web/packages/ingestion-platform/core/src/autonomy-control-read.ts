import { Client, type QueryResult } from "pg";

import {
  buildAutonomyDashboardView,
  mapPersistedPolicyRow,
  mapPersistedRunRow,
  type AutonomyDashboardView
} from "./autonomy-read-model.js";
import { resolveAutonomyDrainBatchPlanKey } from "./batch-plan-selection.js";
import { loadBatchQueueSnapshot, type BatchQueueControlReadPgClientLike } from "./batch-queue-control-read.js";
import { loadProductionPackageWaveApprovalContext } from "./batch-production-package-wave-read.js";
import { createBoundedPostgresReadClientConfig } from "./postgres-read-timeouts.js";

/**
 * Live read of autonomy policy/run rows into `AutonomyDashboardView`.
 * Read-path only — never executes cycles or mutates control-plane state.
 */

export interface AutonomyControlReadPgClientLike {
  query<T extends Record<string, unknown> = Record<string, unknown>>(
    sql: string,
    values?: unknown[]
  ): Promise<QueryResult<T>>;
}

export interface LoadAutonomyDashboardInput {
  connectionString?: string;
  client?: AutonomyControlReadPgClientLike;
  projectKey: string;
  targetKey?: string;
  policyKey?: string;
  batchPlanKey?: string;
}

interface PolicyRow extends Record<string, unknown> {
  id: string;
  policyKey: string;
  projectKey: string;
  sourceKey: string;
  targetKey: string;
  targetEnvironment: "staging" | "production";
  status: string;
  allowedTiers: unknown;
  allowedGeographies: unknown;
  allowedCategories: unknown;
  allowedTransitions: unknown;
  maxUnitsPerCycle: number;
  maxRowsPerCycle: number;
  rollingLimits: Record<string, unknown>;
  guardThresholds: Record<string, unknown>;
  productionInboxHandoffPolicy: Record<string, unknown>;
  policyVersion: number;
  rampMode: string | null;
  approvedBy: string | null;
  approvedAuditId: string | null;
  approvalReason: string | null;
  summary: Record<string, unknown> | null;
  updatedAt: string | Date | null;
}

interface RunRow extends Record<string, unknown> {
  runKey: string;
  phase: string;
  status: string;
  actorType: string;
  actorId: string;
  selectedUnits: unknown;
  scannedCount: number;
  advancedCount: number;
  blockedCount: number;
  skippedCount: number;
  pauseReason: string | null;
  recommendedAction: Record<string, unknown> | null;
  dryRunExecutionKey: string | null;
  waveKey: string | null;
  packageKey: string | null;
  startedAt: string | Date | null;
  completedAt: string | Date | null;
  createdAt: string | Date | null;
}

const UNDEFINED_TABLE = "42P01";

export async function loadAutonomyDashboard(
  input: LoadAutonomyDashboardInput
): Promise<AutonomyDashboardView | null> {
  if (!input.client && !input.connectionString) {
    throw new Error("Autonomy control read requires a server-side connection string or client.");
  }

  const ownedClient = input.client
    ? undefined
    : new Client(createBoundedPostgresReadClientConfig(input.connectionString!));
  const client = input.client ?? ownedClient;
  if (!client) {
    throw new Error("Autonomy control read client could not be initialized.");
  }

  if (ownedClient) {
    await ownedClient.connect();
  }

  try {
    const policy = await loadActivePolicy(client, input);
    if (!policy) {
      return null;
    }

    const latestRun = await loadLatestRun(client, policy.policyId);
    const batchPlanKey = resolveAutonomyDrainBatchPlanKey({
      policy,
      batchPlanKey: input.batchPlanKey
    });
    const queueSnapshot = await loadBatchQueueSnapshot({
      client: client as BatchQueueControlReadPgClientLike,
      projectKey: input.projectKey,
      targetKey: policy.targetKey,
      planKey: batchPlanKey
    });
    const productionPackageApproval = queueSnapshot
      ? await loadProductionPackageWaveApprovalContext({
          client,
          projectKey: input.projectKey,
          targetKey: policy.targetKey
        })
      : null;

    return buildAutonomyDashboardView({
      projectKey: input.projectKey,
      policy,
      latestRun,
      queueSnapshot,
      latestDryRunExecution: queueSnapshot?.latestExecution,
      latestStagingWave: queueSnapshot?.latestWave,
      productionPackage: queueSnapshot?.latestProductionPackageWave,
      productionPackageApproval,
      actor: { type: "autonomous_agent", id: "confluendo-autonomy-read-model" }
    });
  } catch (error) {
    if (isUndefinedTable(error)) {
      return null;
    }
    throw error;
  } finally {
    if (ownedClient) {
      await ownedClient.end();
    }
  }
}

export async function loadAutonomyPolicy(
  client: AutonomyControlReadPgClientLike,
  input: Pick<LoadAutonomyDashboardInput, "projectKey" | "policyKey" | "targetKey">
) {
  return loadActivePolicy(client, input);
}

export async function loadLatestAutonomyRun(client: AutonomyControlReadPgClientLike, policyId: string) {
  return loadLatestRun(client, policyId);
}

async function loadActivePolicy(
  client: AutonomyControlReadPgClientLike,
  input: LoadAutonomyDashboardInput
) {
  const values: unknown[] = [input.projectKey];
  let filters = "";

  if (input.policyKey) {
    filters += " and ap.policy_key = $2";
    values.push(input.policyKey);
  } else if (input.targetKey) {
    filters += " and ap.target_key = $2";
    values.push(input.targetKey);
  }

  const result = await client.query<PolicyRow>(
    `
      select
        ap.id::text as id,
        ap.policy_key as "policyKey",
        p.project_key as "projectKey",
        ap.source_key as "sourceKey",
        ap.target_key as "targetKey",
        ap.target_environment as "targetEnvironment",
        ap.status,
        ap.allowed_tiers as "allowedTiers",
        ap.allowed_geographies as "allowedGeographies",
        ap.allowed_categories as "allowedCategories",
        ap.allowed_transitions as "allowedTransitions",
        ap.max_units_per_cycle as "maxUnitsPerCycle",
        ap.max_rows_per_cycle as "maxRowsPerCycle",
        ap.rolling_limits as "rollingLimits",
        ap.guard_thresholds as "guardThresholds",
        ap.production_inbox_handoff_policy as "productionInboxHandoffPolicy",
        ap.policy_version as "policyVersion",
        to_jsonb(ap)->>'ramp_mode' as "rampMode",
        ap.approved_by as "approvedBy",
        ap.approved_audit_id as "approvedAuditId",
        ap.approval_reason as "approvalReason",
        ap.summary,
        ap.updated_at as "updatedAt"
      from ingestion_platform.ingestion_autonomy_policies ap
      join ingestion_platform.ingestion_projects p on p.id = ap.project_id
      where p.project_key = $1
        and ap.status in ('active', 'paused')
        ${filters}
      order by ap.updated_at desc, ap.id desc
      limit 1
    `,
    values
  );

  const row = result.rows[0];
  if (!row) {
    return null;
  }

  return mapPersistedPolicyRow({
    ...row,
    status: row.status as PolicyRow["status"] & "active"
  });
}

async function loadLatestRun(client: AutonomyControlReadPgClientLike, policyId: string) {
  try {
    const result = await client.query<RunRow>(
      `
        select
          run_key as "runKey",
          phase,
          status,
          actor_type as "actorType",
          actor_id as "actorId",
          selected_units as "selectedUnits",
          scanned_count as "scannedCount",
          advanced_count as "advancedCount",
          blocked_count as "blockedCount",
          skipped_count as "skippedCount",
          pause_reason as "pauseReason",
          recommended_action as "recommendedAction",
          dry_run_execution_key as "dryRunExecutionKey",
          wave_key as "waveKey",
          package_key as "packageKey",
          started_at as "startedAt",
          completed_at as "completedAt",
          created_at as "createdAt"
        from ingestion_platform.ingestion_autonomy_runs
        where policy_id = $1::bigint
        order by created_at desc, id desc
        limit 1
      `,
      [policyId]
    );
    const row = result.rows[0];
    if (!row) {
      return null;
    }
    return mapPersistedRunRow({
      ...row,
      phase: row.phase as RunRow["phase"] & "planning",
      status: row.status as RunRow["status"] & "started"
    });
  } catch (error) {
    if (isUndefinedTable(error)) {
      return null;
    }
    throw error;
  }
}

function isUndefinedTable(error: unknown): boolean {
  return typeof error === "object" && error !== null && "code" in error && error.code === UNDEFINED_TABLE;
}

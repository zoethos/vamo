import { Client, type QueryResult } from "pg";

import type { ProgressiveRunReport } from "./progressive-run.js";
import type {
  CanaryShipmentState,
  CanaryShipmentStatus,
  ProgressiveBacklogEntryInput,
  ProgressiveRunSnapshot,
  ProgressiveWorkStatus
} from "./progressive-read-model.js";
import { deriveReviewedCanaryBounds } from "./progressive-read-model.js";
import type { SafetyMode, ScheduleProposal, TargetTier } from "./schedule-proposal.js";
import type { TargetScorecard } from "./target-scorecard.js";

/**
 * Live read of the progressive scheduling backlog
 * (`ingestion_platform.ingestion_schedule_proposals`) into the dashboard's
 * `ProgressiveRunSnapshot`. Platform-owned and consumer-generic: it reads only
 * the platform schema and returns the same pure-policy shapes the core produces.
 *
 * Read-path only. This module never schedules, executes, or writes a run — it
 * surfaces what the control plane already holds, and returns `null` so the
 * dashboard falls back to its bundled sample when nothing is present.
 */

export interface ProgressiveControlReadPgClientLike {
  query<T extends Record<string, unknown> = Record<string, unknown>>(
    sql: string,
    values?: unknown[]
  ): Promise<QueryResult<T>>;
}

export interface LoadProgressiveRunSnapshotInput {
  connectionString?: string;
  client?: ProgressiveControlReadPgClientLike;
  projectKey: string;
}

interface ProposalRow extends Record<string, unknown> {
  targetKey: string;
  workStatus: string;
  tier: string;
  safetyMode: string;
  scorecard: TargetScorecard;
  proposal: ScheduleProposal | null;
  runReport: ProgressiveRunReport | null;
}

interface ShipmentRow extends Record<string, unknown> {
  shipmentKey: string;
  status: string;
  mode: string;
  createdAt: string | Date | null;
  summary: { approvalAuditId?: unknown } | null;
}

// Postgres "undefined_table" — an older control DB without the progressive table
// should degrade to the sample, never crash the dashboard render.
const UNDEFINED_TABLE = "42P01";

// The shipment_key the staging-canary recorder writes:
// `staging-canary:<target_key>:approval:<approvalAuditId>`.
const CANARY_SHIPMENT_KEY_PATTERN = /^staging-canary:(.+):approval:(.+)$/;
const CANARY_SHIPMENT_STATUSES: ReadonlySet<CanaryShipmentStatus> = new Set([
  "planned",
  "dry_run",
  "approved",
  "shipping",
  "succeeded",
  "failed",
  "cancelled"
]);

/**
 * Returns the progressive snapshot for a project, or `null` when the table is
 * absent or holds no rows for the project — letting the caller fall back to the
 * bundled sample instead of failing the dashboard render.
 */
export async function loadProgressiveRunSnapshot(
  input: LoadProgressiveRunSnapshotInput
): Promise<ProgressiveRunSnapshot | null> {
  if (!input.client && !input.connectionString) {
    throw new Error("Progressive control read requires a server-side connection string or client.");
  }

  const ownedClient = input.client ? undefined : new Client({ connectionString: input.connectionString });
  const client = input.client ?? ownedClient;
  if (!client) {
    throw new Error("Progressive control read client could not be initialized.");
  }

  if (ownedClient) {
    await ownedClient.connect();
  }

  try {
    const result = await client.query<ProposalRow>(
      `
        select
          sp.target_key as "targetKey",
          sp.work_status as "workStatus",
          sp.tier as tier,
          sp.safety_mode as "safetyMode",
          sp.scorecard as scorecard,
          sp.proposal as proposal,
          sp.run_report as "runReport"
        from ingestion_platform.ingestion_schedule_proposals sp
        join ingestion_platform.ingestion_projects p on p.id = sp.project_id
        where p.project_key = $1
        order by sp.created_at desc, sp.id desc
      `,
      [input.projectKey]
    );

    if (result.rows.length === 0) {
      return null;
    }

    const shipments = await loadCanaryShipmentMap(client, input.projectKey);

    return {
      entries: result.rows.map((row) => toEntry(row, shipments.get(row.targetKey) ?? null))
    };
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

/**
 * Loads the latest staging-canary shipment per target for a project, keyed by
 * target_key parsed from the shipment_key. Returns an empty map (never throws)
 * when the shipment ledger is absent on an older control DB, so the dashboard
 * still renders. Rows are ordered newest-first, so the first row seen for each
 * target wins.
 */
async function loadCanaryShipmentMap(
  client: ProgressiveControlReadPgClientLike,
  projectKey: string
): Promise<Map<string, CanaryShipmentState>> {
  const map = new Map<string, CanaryShipmentState>();
  try {
    const result = await client.query<ShipmentRow>(
      `
        select
          s.shipment_key as "shipmentKey",
          s.status as status,
          s.mode as mode,
          s.created_at as "createdAt",
          s.summary as summary
        from ingestion_platform.ingestion_shipments s
        join ingestion_platform.ingestion_projects p on p.id = s.project_id
        where p.project_key = $1
          and s.shipment_key like 'staging-canary:%:approval:%'
        order by s.created_at desc, s.id desc
      `,
      [projectKey]
    );

    for (const row of result.rows) {
      const parsed = parseShipmentRow(row);
      if (parsed && !map.has(parsed.targetKey)) {
        map.set(parsed.targetKey, parsed.state);
      }
    }
  } catch (error) {
    if (!isUndefinedTable(error)) {
      throw error;
    }
  }
  return map;
}

function parseShipmentRow(
  row: ShipmentRow
): { targetKey: string; state: CanaryShipmentState } | null {
  const match = CANARY_SHIPMENT_KEY_PATTERN.exec(row.shipmentKey ?? "");
  if (!match) {
    return null;
  }
  const targetKey = match[1];
  const approvalFromKey = match[2];
  if (!CANARY_SHIPMENT_STATUSES.has(row.status as CanaryShipmentStatus)) {
    return null;
  }

  return {
    targetKey,
    state: {
      status: row.status as CanaryShipmentStatus,
      mode: row.mode,
      shipmentKey: row.shipmentKey,
      createdAt: toIso(row.createdAt),
      approvalAuditId: resolveApprovalAuditId(row.summary, approvalFromKey)
    }
  };
}

function resolveApprovalAuditId(
  summary: ShipmentRow["summary"],
  fallback: string | undefined
): string | undefined {
  const fromSummary = summary?.approvalAuditId;
  if (typeof fromSummary === "string" && fromSummary.trim().length > 0) {
    return fromSummary.trim();
  }
  if (typeof fromSummary === "number" && Number.isFinite(fromSummary)) {
    return String(fromSummary);
  }
  return fallback && fallback.length > 0 ? fallback : undefined;
}

function toIso(value: string | Date | null): string {
  if (value instanceof Date) {
    return value.toISOString();
  }
  if (typeof value === "string" && value.length > 0) {
    const parsed = new Date(value);
    return Number.isNaN(parsed.getTime()) ? value : parsed.toISOString();
  }
  return new Date(0).toISOString();
}

function toEntry(
  row: ProposalRow,
  canaryShipment: CanaryShipmentState | null
): ProgressiveBacklogEntryInput {
  const report = row.runReport ?? undefined;
  return {
    workStatus: row.workStatus as ProgressiveWorkStatus,
    scorecard: row.scorecard,
    tier: row.tier as TargetTier,
    safetyMode: row.safetyMode as SafetyMode,
    canaryBounds: deriveReviewedCanaryBounds({ proposal: row.proposal, report }),
    report,
    scheduledApprovalDescription: report ? undefined : row.proposal?.approval.description,
    canaryShipment
  };
}

function isUndefinedTable(error: unknown): boolean {
  return (
    typeof error === "object" &&
    error !== null &&
    "code" in error &&
    (error as { code?: unknown }).code === UNDEFINED_TABLE
  );
}

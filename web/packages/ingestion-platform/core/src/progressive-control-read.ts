import { Client, type QueryResult } from "pg";

import type { ProgressiveRunReport } from "./progressive-run.js";
import type {
  ProgressiveBacklogEntryInput,
  ProgressiveRunSnapshot,
  ProgressiveWorkStatus
} from "./progressive-read-model.js";
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
  workStatus: string;
  tier: string;
  safetyMode: string;
  scorecard: TargetScorecard;
  proposal: ScheduleProposal | null;
  runReport: ProgressiveRunReport | null;
}

// Postgres "undefined_table" — an older control DB without the progressive table
// should degrade to the sample, never crash the dashboard render.
const UNDEFINED_TABLE = "42P01";

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

    return { entries: result.rows.map(toEntry) };
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

function toEntry(row: ProposalRow): ProgressiveBacklogEntryInput {
  const report = row.runReport ?? undefined;
  return {
    workStatus: row.workStatus as ProgressiveWorkStatus,
    scorecard: row.scorecard,
    tier: row.tier as TargetTier,
    safetyMode: row.safetyMode as SafetyMode,
    report,
    scheduledApprovalDescription: report ? undefined : row.proposal?.approval.description
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

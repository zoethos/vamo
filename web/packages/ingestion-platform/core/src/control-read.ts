import { Client, type QueryResult } from "pg";

import type { IngestionTaskStatus } from "./control-models.js";
import type {
  ControlEventRow,
  ControlEventSeverity,
  ControlInstanceRow,
  ControlMetrics,
  ControlPlaneSnapshot,
  ControlTargetRow
} from "./read-model.js";

/**
 * Live read of operational control-plane state into the dashboard's
 * ControlPlaneSnapshot. This is the platform-owned, consumer-generic half: it
 * reads only `ingestion_platform.*` tables. Cache-business metrics (canonicals
 * promoted, cache yield, etc.) are NOT in the control plane and are left at zero
 * here for the host to fill from its own product cache.
 */

export interface ControlReadPgClientLike {
  query<T extends Record<string, unknown> = Record<string, unknown>>(
    sql: string,
    values?: unknown[]
  ): Promise<QueryResult<T>>;
}

export interface LoadControlPlaneSnapshotInput {
  connectionString?: string;
  client?: ControlReadPgClientLike;
  projectKey: string;
  now?: string;
  eventLimit?: number;
}

const DEFAULT_EVENT_LIMIT = 12;

interface ProjectRow extends Record<string, unknown> {
  id: string;
}

interface InstanceRow extends Record<string, unknown> {
  workerId: string;
  status: IngestionTaskStatus | null;
  currentTarget: string | null;
  heartbeatAt: string | Date | null;
  cursor: string | null;
}

interface TargetRow extends Record<string, unknown> {
  displayName: string;
  adapter: string;
  safetyMode: string;
  status: IngestionTaskStatus | null;
  workerId: string | null;
  checkpoint: string | null;
  lastSignal: string | null;
}

interface EventRow extends Record<string, unknown> {
  createdAt: string | Date;
  signal: string | null;
  eventType: string;
  message: string;
  severity: string;
  targetName: string | null;
}

interface MetricRow extends Record<string, unknown> {
  sourceCount: string;
  promotionTargetCount: string;
  oldestCheckpointLagSeconds: string | null;
}

/**
 * Returns the operational snapshot, or `null` when the project key does not
 * exist — letting the caller fall back to sample/empty data instead of failing
 * the dashboard render.
 */
export async function loadControlPlaneSnapshot(
  input: LoadControlPlaneSnapshotInput
): Promise<ControlPlaneSnapshot | null> {
  if (!input.client && !input.connectionString) {
    throw new Error("Control-plane read requires a server-side connection string or client.");
  }

  const ownedClient = input.client ? undefined : new Client({ connectionString: input.connectionString });
  const client = input.client ?? ownedClient;
  if (!client) {
    throw new Error("Control-plane read client could not be initialized.");
  }

  if (ownedClient) {
    await ownedClient.connect();
  }

  try {
    const projectResult = await client.query<ProjectRow>(
      `
        select id::text as id
        from ingestion_platform.ingestion_projects
        where project_key = $1
        limit 1
      `,
      [input.projectKey]
    );
    const projectId = projectResult.rows[0]?.id;
    if (!projectId) {
      return null;
    }

    const now = input.now ?? new Date().toISOString();
    const eventLimit = input.eventLimit ?? DEFAULT_EVENT_LIMIT;

    const [instances, targets, events, metrics] = await Promise.all([
      loadInstances(client, projectId),
      loadTargets(client, projectId),
      loadEvents(client, projectId, eventLimit),
      loadOperationalMetrics(client, projectId)
    ]);

    return {
      instances: instances.map((row) => toInstance(row, now)),
      targets: targets.map(toTarget),
      events: events.map(toEvent),
      metrics: toMetrics(metrics, targets)
    };
  } finally {
    if (ownedClient) {
      await ownedClient.end();
    }
  }
}

async function loadInstances(
  client: ControlReadPgClientLike,
  projectId: string
): Promise<InstanceRow[]> {
  const result = await client.query<InstanceRow>(
    `
      select
        leases.worker_id as "workerId",
        tasks.status as status,
        targets.display_name as "currentTarget",
        leases.heartbeat_at as "heartbeatAt",
        checkpoints.last_record_key as cursor
      from ingestion_platform.ingestion_worker_leases leases
      join ingestion_platform.ingestion_tasks tasks on tasks.id = leases.task_id
      left join ingestion_platform.ingestion_targets targets on targets.id = tasks.target_id
      left join lateral (
        select last_record_key
        from ingestion_platform.ingestion_checkpoints cp
        where cp.target_id = tasks.target_id
        order by cp.updated_at desc
        limit 1
      ) checkpoints on true
      where tasks.project_id = $1::bigint
        and leases.status = 'active'
      order by leases.worker_id
    `,
    [projectId]
  );
  return result.rows;
}

async function loadTargets(
  client: ControlReadPgClientLike,
  projectId: string
): Promise<TargetRow[]> {
  const result = await client.query<TargetRow>(
    `
      select
        targets.display_name as "displayName",
        targets.adapter as adapter,
        targets.safety_mode as "safetyMode",
        latest_task.status as status,
        latest_lease.worker_id as "workerId",
        checkpoints.last_record_key as checkpoint,
        latest_event.signal as "lastSignal"
      from ingestion_platform.ingestion_targets targets
      left join lateral (
        select id, status
        from ingestion_platform.ingestion_tasks t
        where t.target_id = targets.id
        order by t.updated_at desc
        limit 1
      ) latest_task on true
      left join lateral (
        select worker_id
        from ingestion_platform.ingestion_worker_leases l
        where l.task_id = latest_task.id and l.status = 'active'
        order by l.heartbeat_at desc
        limit 1
      ) latest_lease on true
      left join lateral (
        select last_record_key
        from ingestion_platform.ingestion_checkpoints cp
        where cp.target_id = targets.id
        order by cp.updated_at desc
        limit 1
      ) checkpoints on true
      left join lateral (
        select e.signal
        from ingestion_platform.ingestion_events e
        where e.task_id = latest_task.id and e.signal is not null
        order by e.created_at desc
        limit 1
      ) latest_event on true
      where targets.project_id = $1::bigint
      order by targets.id
    `,
    [projectId]
  );
  return result.rows;
}

async function loadEvents(
  client: ControlReadPgClientLike,
  projectId: string,
  limit: number
): Promise<EventRow[]> {
  const result = await client.query<EventRow>(
    `
      select
        events.created_at as "createdAt",
        events.signal as signal,
        events.event_type as "eventType",
        events.message as message,
        events.severity as severity,
        targets.display_name as "targetName"
      from ingestion_platform.ingestion_events events
      left join ingestion_platform.ingestion_tasks tasks on tasks.id = events.task_id
      left join ingestion_platform.ingestion_targets targets on targets.id = tasks.target_id
      where events.project_id = $1::bigint
      order by events.created_at desc
      limit $2::int
    `,
    [projectId, limit]
  );
  return result.rows;
}

async function loadOperationalMetrics(
  client: ControlReadPgClientLike,
  projectId: string
): Promise<MetricRow> {
  const result = await client.query<MetricRow>(
    `
      select
        (select count(*) from ingestion_platform.ingestion_sources s where s.project_id = $1::bigint)::text as "sourceCount",
        (select count(*) from ingestion_platform.ingestion_targets t
           where t.project_id = $1::bigint and t.safety_mode = 'approved_write')::text as "promotionTargetCount",
        (select extract(epoch from (now() - min(cp.updated_at)))::bigint
           from ingestion_platform.ingestion_checkpoints cp
           where cp.project_id = $1::bigint)::text as "oldestCheckpointLagSeconds"
    `,
    [projectId]
  );
  return (
    result.rows[0] ?? {
      sourceCount: "0",
      promotionTargetCount: "0",
      oldestCheckpointLagSeconds: null
    }
  );
}

function toInstance(row: InstanceRow, now: string): ControlInstanceRow {
  return {
    id: row.workerId,
    role: "Worker",
    status: row.status ?? "queued",
    currentTarget: row.currentTarget ?? "Unassigned",
    heartbeatSecondsAgo: heartbeatSecondsAgo(row.heartbeatAt, now),
    cursor: row.cursor ?? "—",
    throughput: "—",
    network: "—"
  };
}

function toTarget(row: TargetRow): ControlTargetRow {
  return {
    name: row.displayName,
    source: row.adapter,
    scope: row.safetyMode === "approved_write" ? "Promotion stream" : "Source seed",
    instanceId: row.workerId ?? "unassigned",
    status: row.status ?? "queued",
    checkpoint: row.checkpoint ?? "—",
    throughput: "—",
    lastSignal: row.lastSignal ?? "—"
  };
}

function toEvent(row: EventRow): ControlEventRow {
  return {
    time: toTimeLabel(row.createdAt),
    signal: row.signal ?? row.eventType,
    targetName: row.targetName ?? "—",
    detail: row.message,
    severity: toSeverity(row.severity)
  };
}

function toMetrics(row: MetricRow, targets: TargetRow[]): ControlMetrics {
  const promotionStreamTargets = Number(row.promotionTargetCount) || 0;
  return {
    // Cache-business metrics are not in the control plane; the host fills these.
    cacheYieldPct: 0,
    oldestCheckpointLagSeconds: Number(row.oldestCheckpointLagSeconds) || 0,
    sourceSeedTargets: Math.max(targets.length - promotionStreamTargets, 0),
    promotionStreamTargets,
    canonicalsPromoted: 0,
    observedAliases: 0,
    pendingReview: 0,
    policyBlocks: 0,
    duplicateMerges: 0,
    liveCallsAvoided: 0
  };
}

function heartbeatSecondsAgo(value: string | Date | null, now: string): number | null {
  if (!value) {
    return null;
  }
  const heartbeatMs = value instanceof Date ? value.getTime() : Date.parse(value);
  const nowMs = Date.parse(now);
  if (!Number.isFinite(heartbeatMs) || !Number.isFinite(nowMs)) {
    return null;
  }
  return Math.max(Math.round((nowMs - heartbeatMs) / 1000), 0);
}

function toTimeLabel(value: string | Date): string {
  const date = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(date.getTime())) {
    return "—";
  }
  return date.toISOString().slice(11, 19);
}

const KNOWN_SEVERITIES: ReadonlySet<string> = new Set(["debug", "info", "warn", "error"]);

function toSeverity(value: string): ControlEventSeverity {
  const normalized = value.toLowerCase();
  if (normalized === "error") {
    return "error";
  }
  if (normalized === "warn") {
    return "warn";
  }
  if (normalized === "debug" || !KNOWN_SEVERITIES.has(normalized)) {
    return "info";
  }
  return "info";
}

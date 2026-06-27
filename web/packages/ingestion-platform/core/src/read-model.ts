import type { IngestionTaskStatus } from "./control-models.js";

/**
 * Read model: a pure transform from control-plane rows into the admin dashboard
 * view. It is the only thing the admin UI consumes — the UI never reads control
 * tables directly. Keep this module dependency-free (no node/pg/fs imports) so it
 * is portable and safe to evaluate server-side or in a bundle.
 */

/* ----------------------------- View types -------------------------------- */
/* What the admin page renders. Mirrors the existing static dashboard shape. */

export type IngestionTone = "good" | "watch" | "danger" | "neutral";

export type IngestionStatus =
  | "running"
  | "paused"
  | "stopped"
  | "blocked"
  | "queued"
  | "complete";

export interface IngestionSignal {
  label: string;
  value: string;
  detail: string;
  tone: IngestionTone;
}

export interface IngestionAction {
  label: string;
  detail: string;
  tone: "primary" | "neutral" | "danger";
}

export interface IngestionInstance {
  id: string;
  role: string;
  status: IngestionStatus;
  currentTarget: string;
  heartbeat: string;
  cursor: string;
  throughput: string;
  network: string;
}

export interface IngestionTarget {
  id: string;
  name: string;
  source: string;
  scope: string;
  instance: string;
  status: IngestionStatus;
  checkpoint: string;
  throughput: string;
  lastSignal: string;
  nextAction: string;
}

export interface IngestionEvent {
  time: string;
  signal: string;
  target: string;
  detail: string;
  tone: IngestionTone;
}

export interface IngestionStat {
  label: string;
  value: string;
  detail: string;
}

export interface IngestionDashboardView {
  signals: IngestionSignal[];
  actions: IngestionAction[];
  instances: IngestionInstance[];
  targets: IngestionTarget[];
  events: IngestionEvent[];
  stats: IngestionStat[];
  policyLocks: string[];
}

/* --------------------------- Control-plane input -------------------------- */
/* Row-shaped data the platform owns (runs/tasks/leases/events/rollups). This is
   what a control API would return; here it is fed as a snapshot. */

export interface ControlInstanceRow {
  id: string;
  role: string;
  status: IngestionTaskStatus;
  currentTarget: string;
  /** Seconds since last heartbeat; null means idle/ready (no active lease). */
  heartbeatSecondsAgo: number | null;
  cursor: string;
  throughput: string;
  network: string;
}

export interface ControlTargetRow {
  id: string;
  name: string;
  source: string;
  scope: string;
  instanceId: string;
  status: IngestionTaskStatus;
  checkpoint: string;
  throughput: string;
  lastSignal: string;
}

export type ControlEventSeverity = "success" | "info" | "warn" | "error";

export interface ControlEventRow {
  time: string;
  signal: string;
  targetName: string;
  detail: string;
  severity: ControlEventSeverity;
}

export interface ControlMetrics {
  cacheYieldPct: number;
  oldestCheckpointLagSeconds: number;
  sourceSeedTargets: number;
  promotionStreamTargets: number;
  canonicalsPromoted: number;
  observedAliases: number;
  pendingReview: number;
  policyBlocks: number;
  duplicateMerges: number;
  liveCallsAvoided: number;
}

export interface ControlPlaneSnapshot {
  instances: ControlInstanceRow[];
  targets: ControlTargetRow[];
  events: ControlEventRow[];
  metrics: ControlMetrics;
}

/* ------------------------------- Mappings -------------------------------- */

const STATUS_TO_VIEW: Record<IngestionTaskStatus, IngestionStatus> = {
  queued: "queued",
  running: "running",
  paused: "paused",
  succeeded: "complete",
  failed: "stopped",
  blocked: "blocked",
  cancelled: "stopped"
};

const VIEW_STATUS_TONE: Record<IngestionStatus, IngestionTone> = {
  running: "good",
  complete: "good",
  queued: "neutral",
  paused: "watch",
  blocked: "danger",
  stopped: "danger"
};

const VIEW_STATUS_NEXT_ACTION: Record<IngestionStatus, string> = {
  running: "Pause",
  paused: "Resume",
  queued: "Start",
  blocked: "Review",
  stopped: "Restart",
  complete: "Review"
};

const EVENT_SEVERITY_TONE: Record<ControlEventSeverity, IngestionTone> = {
  success: "good",
  info: "neutral",
  warn: "watch",
  error: "danger"
};

/** Operator capabilities and invariants — fixed affordances, not row-derived. */
const CLUSTER_ACTIONS: IngestionAction[] = [
  {
    label: "Start all",
    detail: "Acquire worker leases and resume eligible targets.",
    tone: "primary"
  },
  {
    label: "Pause all",
    detail: "Drain in-flight pages, commit cursors, keep leases visible.",
    tone: "neutral"
  },
  {
    label: "Shutdown",
    detail: "Stop containers after checkpoint flush.",
    tone: "neutral"
  },
  {
    label: "Reset failed",
    detail: "Clear failed leases only after operator confirmation.",
    tone: "danger"
  }
];

const POLICY_LOCKS: string[] = [
  "No rotating VPN, proxy evasion, or identity cycling.",
  "Provider payload storage follows modeled policy flags.",
  "Google stays live-only unless a later policy slice explicitly allows retention.",
  "Global cache rows cannot carry user identifiers.",
  "Observation writes and promotion checks never block trip creation."
];

/* ------------------------------ Transform -------------------------------- */

export function buildIngestionDashboardView(
  snapshot: ControlPlaneSnapshot
): IngestionDashboardView {
  const instances = snapshot.instances.map(toViewInstance);
  const targets = snapshot.targets.map(toViewTarget);
  const events = snapshot.events.map(toViewEvent);

  return {
    signals: buildSignals(instances, targets, snapshot.metrics),
    actions: CLUSTER_ACTIONS,
    instances,
    targets,
    events,
    stats: buildStats(snapshot.metrics),
    policyLocks: POLICY_LOCKS
  };
}

function toViewInstance(row: ControlInstanceRow): IngestionInstance {
  return {
    id: row.id,
    role: row.role,
    status: STATUS_TO_VIEW[row.status],
    currentTarget: row.currentTarget,
    heartbeat: formatHeartbeat(row.heartbeatSecondsAgo),
    cursor: row.cursor,
    throughput: row.throughput,
    network: row.network
  };
}

function toViewTarget(row: ControlTargetRow): IngestionTarget {
  const status = STATUS_TO_VIEW[row.status];
  return {
    id: row.id,
    name: row.name,
    source: row.source,
    scope: row.scope,
    instance: row.instanceId,
    status,
    checkpoint: row.checkpoint,
    throughput: row.throughput,
    lastSignal: row.lastSignal,
    nextAction: VIEW_STATUS_NEXT_ACTION[status]
  };
}

function toViewEvent(row: ControlEventRow): IngestionEvent {
  return {
    time: row.time,
    signal: row.signal,
    target: row.targetName,
    detail: row.detail,
    tone: EVENT_SEVERITY_TONE[row.severity]
  };
}

export function viewStatusTone(status: IngestionStatus): IngestionTone {
  return VIEW_STATUS_TONE[status];
}

function buildSignals(
  instances: IngestionInstance[],
  targets: IngestionTarget[],
  metrics: ControlMetrics
): IngestionSignal[] {
  const active = instances.filter((instance) => instance.status === "running").length;
  const paused = instances.filter((instance) => instance.status === "paused").length;
  const queued = instances.filter((instance) => instance.status === "queued").length;
  const online = active + paused + queued;

  return [
    {
      label: "Workers",
      value: `${online} online`,
      detail: `${active} active, ${paused} paused, ${queued} queued`,
      tone: online > 0 ? "good" : "watch"
    },
    {
      label: "Targets",
      value: `${targets.length} tracked`,
      detail: `${metrics.sourceSeedTargets} source seeds, ${metrics.promotionStreamTargets} promotion streams`,
      tone: "neutral"
    },
    {
      label: "Cache yield",
      value: `${metrics.cacheYieldPct}%`,
      detail: "Projected live-provider calls avoided",
      tone: metrics.cacheYieldPct >= 60 ? "good" : "watch"
    },
    {
      label: "Recovery",
      value: formatLag(metrics.oldestCheckpointLagSeconds),
      detail: "Oldest committed checkpoint lag",
      tone: metrics.oldestCheckpointLagSeconds > 60 ? "watch" : "good"
    }
  ];
}

function buildStats(metrics: ControlMetrics): IngestionStat[] {
  return [
    {
      label: "Canonicals promoted",
      value: groupThousands(metrics.canonicalsPromoted),
      detail: "Trusted source match or cross-user corroboration."
    },
    {
      label: "Observed aliases",
      value: groupThousands(metrics.observedAliases),
      detail: "User-scoped until promotion gates pass."
    },
    {
      label: "Pending review",
      value: groupThousands(metrics.pendingReview),
      detail: "Mostly image-license and collision checks."
    },
    {
      label: "Policy blocks",
      value: groupThousands(metrics.policyBlocks),
      detail: "All blocked before reusable cache write."
    },
    {
      label: "Duplicate merges",
      value: groupThousands(metrics.duplicateMerges),
      detail: "Canonical merges from source IDs and fuzzy aliases."
    },
    {
      label: "Calls avoided",
      value: formatThousandsShort(metrics.liveCallsAvoided),
      detail: "Estimated fresh provider calls avoided by cache hits."
    }
  ];
}

function formatHeartbeat(secondsAgo: number | null): string {
  if (secondsAgo === null) {
    return "Ready";
  }
  if (secondsAgo < 60) {
    return `${secondsAgo}s ago`;
  }
  return `${Math.floor(secondsAgo / 60)}m ago`;
}

function formatLag(seconds: number): string {
  if (seconds < 120) {
    return `${seconds}s`;
  }
  return `${Math.floor(seconds / 60)}m`;
}

/** Locale-independent grouping so the view is deterministic across environments. */
function groupThousands(value: number): string {
  return value.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ",");
}

function formatThousandsShort(value: number): string {
  if (value < 1000) {
    return value.toString();
  }
  return `${(value / 1000).toFixed(1)}k`;
}

/* ----------------------------- Sample data ------------------------------- */
/* A representative control-plane snapshot so the admin shell renders from the
   read model before a live control API exists. Not authored by the UI. */

export const sampleControlPlaneSnapshot: ControlPlaneSnapshot = {
  instances: [
    {
      id: "worker-pc-01",
      role: "Open dataset loader",
      status: "running",
      currentTarget: "FSQ OS Places - Italy",
      heartbeatSecondsAgo: 15,
      cursor: "fsq.it.0048129",
      throughput: "1,840 rows/min",
      network: "Fixed egress, no proxy rotation"
    },
    {
      id: "worker-pc-02",
      role: "Wikidata enrichment",
      status: "running",
      currentTarget: "Rome monuments image candidates",
      heartbeatSecondsAgo: 19,
      cursor: "Q243.01872",
      throughput: "620 claims/min",
      network: "Provider-compliant request budget"
    },
    {
      id: "worker-pc-03",
      role: "Alias promotion verifier",
      status: "paused",
      currentTarget: "User observation corroboration",
      heartbeatSecondsAgo: 120,
      cursor: "observation.092114",
      throughput: "Paused by operator",
      network: "Private Vamo data only"
    },
    {
      id: "staging-export-01",
      role: "Incremental export",
      status: "queued",
      currentTarget: "Staging delta package",
      heartbeatSecondsAgo: null,
      cursor: "delta.2026-06-26T08:00Z",
      throughput: "Waiting on promotion gate",
      network: "Supabase staging writer"
    }
  ],
  targets: [
    {
      id: "fsq-os-places-it",
      name: "FSQ OS Places - Italy",
      source: "FSQ OS Places",
      scope: "POIs, coordinates, categories",
      instanceId: "worker-pc-01",
      status: "running",
      checkpoint: "fsq.it.0048129",
      throughput: "1,840 rows/min",
      lastSignal: "checkpoint_committed"
    },
    {
      id: "geonames-populated-places-eu",
      name: "GeoNames populated places - EU",
      source: "GeoNames",
      scope: "Settlements, country, population",
      instanceId: "worker-pc-01",
      status: "queued",
      checkpoint: "geonames.eu.001902",
      throughput: "Ready",
      lastSignal: "waiting_for_slot"
    },
    {
      id: "rome-monuments-enrichment",
      name: "Rome monuments enrichment",
      source: "Wikidata + Wikimedia Commons",
      scope: "Descriptions, image license candidates",
      instanceId: "worker-pc-02",
      status: "running",
      checkpoint: "Q243.01872",
      throughput: "620 claims/min",
      lastSignal: "claim_batch_ok"
    },
    {
      id: "venice-visual-candidates",
      name: "Venice visual candidates",
      source: "Wikimedia Commons",
      scope: "Licensed images, attribution rows",
      instanceId: "worker-pc-02",
      status: "paused",
      checkpoint: "commons.venice.000314",
      throughput: "Paused",
      lastSignal: "license_review_required"
    },
    {
      id: "user-alias-corroboration",
      name: "User alias corroboration",
      source: "Vamo observations",
      scope: "Cross-user alias promotion only",
      instanceId: "worker-pc-03",
      status: "paused",
      checkpoint: "observation.092114",
      throughput: "Paused",
      lastSignal: "operator_pause"
    },
    {
      id: "google-visual-rehearsal",
      name: "Google visual rehearsal",
      source: "Google live resolver",
      scope: "Live-only validation, no reusable cache",
      instanceId: "unassigned",
      status: "blocked",
      checkpoint: "policy.google.live-only",
      throughput: "Blocked",
      lastSignal: "policy_guard_blocked_storage"
    },
    {
      id: "staging-incremental-export",
      name: "Staging incremental export",
      source: "Promoted Vamo cache",
      scope: "Canonicals, source refs, attribution",
      instanceId: "staging-export-01",
      status: "queued",
      checkpoint: "delta.2026-06-26T08:00Z",
      throughput: "Ready",
      lastSignal: "awaiting_delta"
    }
  ],
  events: [
    {
      time: "09:14:28",
      signal: "checkpoint_committed",
      targetName: "FSQ OS Places - Italy",
      detail: "Cursor fsq.it.0048129 is durable; restart resumes from the next page.",
      severity: "success"
    },
    {
      time: "09:12:05",
      signal: "license_review_required",
      targetName: "Venice visual candidates",
      detail: "Candidate images paused until attribution and license fields are complete.",
      severity: "warn"
    },
    {
      time: "09:08:51",
      signal: "policy_guard_blocked_storage",
      targetName: "Google visual rehearsal",
      detail: "Live resolver payload cannot enter reusable cross-user cache.",
      severity: "error"
    },
    {
      time: "09:04:16",
      signal: "promotion_delayed",
      targetName: "User alias corroboration",
      detail: "Single-user repetition is user-scoped only; global alias needs distinct-user proof.",
      severity: "info"
    },
    {
      time: "08:58:44",
      signal: "worker_lease_renewed",
      targetName: "Rome monuments enrichment",
      detail: "worker-pc-02 lease renewed; current batch remains resumable.",
      severity: "success"
    }
  ],
  metrics: {
    cacheYieldPct: 72,
    oldestCheckpointLagSeconds: 94,
    sourceSeedTargets: 5,
    promotionStreamTargets: 2,
    canonicalsPromoted: 128440,
    observedAliases: 40120,
    pendingReview: 318,
    policyBlocks: 12,
    duplicateMerges: 871,
    liveCallsAvoided: 31800
  }
};

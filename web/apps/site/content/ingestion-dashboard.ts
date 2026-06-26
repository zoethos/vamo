export type IngestionTone = "good" | "watch" | "danger" | "neutral";

export type IngestionStatus =
  | "running"
  | "paused"
  | "stopped"
  | "blocked"
  | "queued"
  | "complete";

export type IngestionSignal = {
  label: string;
  value: string;
  detail: string;
  tone: IngestionTone;
};

export type IngestionAction = {
  label: string;
  detail: string;
  tone: "primary" | "neutral" | "danger";
};

export type IngestionInstance = {
  id: string;
  role: string;
  status: IngestionStatus;
  currentTarget: string;
  heartbeat: string;
  cursor: string;
  throughput: string;
  network: string;
};

export type IngestionTarget = {
  name: string;
  source: string;
  scope: string;
  instance: string;
  status: IngestionStatus;
  checkpoint: string;
  throughput: string;
  lastSignal: string;
  nextAction: string;
};

export type IngestionEvent = {
  time: string;
  signal: string;
  target: string;
  detail: string;
  tone: IngestionTone;
};

export type IngestionStat = {
  label: string;
  value: string;
  detail: string;
};

export const ingestionSignals: IngestionSignal[] = [
  {
    label: "Workers",
    value: "4 online",
    detail: "2 active, 1 paused, 1 staging exporter",
    tone: "good",
  },
  {
    label: "Targets",
    value: "7 tracked",
    detail: "5 source seeds, 2 promotion streams",
    tone: "neutral",
  },
  {
    label: "Cache yield",
    value: "72%",
    detail: "Projected live-provider calls avoided",
    tone: "good",
  },
  {
    label: "Recovery",
    value: "94s",
    detail: "Oldest committed checkpoint lag",
    tone: "watch",
  },
];

export const ingestionActions: IngestionAction[] = [
  {
    label: "Start all",
    detail: "Acquire worker leases and resume eligible targets.",
    tone: "primary",
  },
  {
    label: "Pause all",
    detail: "Drain in-flight pages, commit cursors, keep leases visible.",
    tone: "neutral",
  },
  {
    label: "Shutdown",
    detail: "Stop containers after checkpoint flush.",
    tone: "neutral",
  },
  {
    label: "Reset failed",
    detail: "Clear failed leases only after operator confirmation.",
    tone: "danger",
  },
];

export const ingestionInstances: IngestionInstance[] = [
  {
    id: "worker-pc-01",
    role: "Open dataset loader",
    status: "running",
    currentTarget: "FSQ OS Places - Italy",
    heartbeat: "15s ago",
    cursor: "fsq.it.0048129",
    throughput: "1,840 rows/min",
    network: "Fixed egress, no proxy rotation",
  },
  {
    id: "worker-pc-02",
    role: "Wikidata enrichment",
    status: "running",
    currentTarget: "Rome monuments image candidates",
    heartbeat: "19s ago",
    cursor: "Q243.01872",
    throughput: "620 claims/min",
    network: "Provider-compliant request budget",
  },
  {
    id: "worker-pc-03",
    role: "Alias promotion verifier",
    status: "paused",
    currentTarget: "User observation corroboration",
    heartbeat: "2m ago",
    cursor: "observation.092114",
    throughput: "Paused by operator",
    network: "Private Vamo data only",
  },
  {
    id: "staging-export-01",
    role: "Incremental export",
    status: "queued",
    currentTarget: "Staging delta package",
    heartbeat: "Ready",
    cursor: "delta.2026-06-26T08:00Z",
    throughput: "Waiting on promotion gate",
    network: "Supabase staging writer",
  },
];

export const ingestionTargets: IngestionTarget[] = [
  {
    name: "FSQ OS Places - Italy",
    source: "FSQ OS Places",
    scope: "POIs, coordinates, categories",
    instance: "worker-pc-01",
    status: "running",
    checkpoint: "fsq.it.0048129",
    throughput: "1,840 rows/min",
    lastSignal: "checkpoint_committed",
    nextAction: "Pause",
  },
  {
    name: "GeoNames populated places - EU",
    source: "GeoNames",
    scope: "Settlements, country, population",
    instance: "worker-pc-01",
    status: "queued",
    checkpoint: "geonames.eu.001902",
    throughput: "Ready",
    lastSignal: "waiting_for_slot",
    nextAction: "Start",
  },
  {
    name: "Rome monuments enrichment",
    source: "Wikidata + Wikimedia Commons",
    scope: "Descriptions, image license candidates",
    instance: "worker-pc-02",
    status: "running",
    checkpoint: "Q243.01872",
    throughput: "620 claims/min",
    lastSignal: "claim_batch_ok",
    nextAction: "Pause",
  },
  {
    name: "Venice visual candidates",
    source: "Wikimedia Commons",
    scope: "Licensed images, attribution rows",
    instance: "worker-pc-02",
    status: "paused",
    checkpoint: "commons.venice.000314",
    throughput: "Paused",
    lastSignal: "license_review_required",
    nextAction: "Resume",
  },
  {
    name: "User alias corroboration",
    source: "Vamo observations",
    scope: "Cross-user alias promotion only",
    instance: "worker-pc-03",
    status: "paused",
    checkpoint: "observation.092114",
    throughput: "Paused",
    lastSignal: "operator_pause",
    nextAction: "Resume",
  },
  {
    name: "Google visual rehearsal",
    source: "Google live resolver",
    scope: "Live-only validation, no reusable cache",
    instance: "unassigned",
    status: "blocked",
    checkpoint: "policy.google.live-only",
    throughput: "Blocked",
    lastSignal: "policy_guard_blocked_storage",
    nextAction: "Review",
  },
  {
    name: "Staging incremental export",
    source: "Promoted Vamo cache",
    scope: "Canonicals, source refs, attribution",
    instance: "staging-export-01",
    status: "queued",
    checkpoint: "delta.2026-06-26T08:00Z",
    throughput: "Ready",
    lastSignal: "awaiting_delta",
    nextAction: "Start",
  },
];

export const ingestionEvents: IngestionEvent[] = [
  {
    time: "09:14:28",
    signal: "checkpoint_committed",
    target: "FSQ OS Places - Italy",
    detail: "Cursor fsq.it.0048129 is durable; restart resumes from the next page.",
    tone: "good",
  },
  {
    time: "09:12:05",
    signal: "license_review_required",
    target: "Venice visual candidates",
    detail: "Candidate images paused until attribution and license fields are complete.",
    tone: "watch",
  },
  {
    time: "09:08:51",
    signal: "policy_guard_blocked_storage",
    target: "Google visual rehearsal",
    detail: "Live resolver payload cannot enter reusable cross-user cache.",
    tone: "danger",
  },
  {
    time: "09:04:16",
    signal: "promotion_delayed",
    target: "User alias corroboration",
    detail: "Single-user repetition is user-scoped only; global alias needs distinct-user proof.",
    tone: "neutral",
  },
  {
    time: "08:58:44",
    signal: "worker_lease_renewed",
    target: "Rome monuments enrichment",
    detail: "worker-pc-02 lease renewed; current batch remains resumable.",
    tone: "good",
  },
];

export const ingestionStats: IngestionStat[] = [
  {
    label: "Canonicals promoted",
    value: "128,440",
    detail: "Trusted source match or cross-user corroboration.",
  },
  {
    label: "Observed aliases",
    value: "40,120",
    detail: "User-scoped until promotion gates pass.",
  },
  {
    label: "Pending review",
    value: "318",
    detail: "Mostly image-license and collision checks.",
  },
  {
    label: "Policy blocks",
    value: "12",
    detail: "All blocked before reusable cache write.",
  },
  {
    label: "Duplicate merges",
    value: "871",
    detail: "Canonical merges from source IDs and fuzzy aliases.",
  },
  {
    label: "Calls avoided",
    value: "31.8k",
    detail: "Estimated fresh provider calls avoided by cache hits.",
  },
];

export const ingestionPolicyLocks = [
  "No rotating VPN, proxy evasion, or identity cycling.",
  "Provider payload storage follows modeled policy flags.",
  "Google stays live-only unless a later policy slice explicitly allows retention.",
  "Global cache rows cannot carry user identifiers.",
  "Observation writes and promotion checks never block trip creation.",
];

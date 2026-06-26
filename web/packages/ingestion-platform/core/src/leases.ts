export type WorkerLeaseStatus = "active" | "released" | "expired";

export interface WorkerLeaseRow {
  id: string;
  taskId: string;
  workerId: string;
  leaseToken: string;
  status: WorkerLeaseStatus;
  heartbeatAt: string;
  expiresAt: string;
  releasedAt?: string | null;
  releaseReason?: string | null;
}

export interface WorkerLeasePatch {
  leaseId: string;
  taskId: string;
  workerId: string;
  previousStatus: WorkerLeaseStatus;
  status: WorkerLeaseStatus;
  releasedAt: string;
  releaseReason: string;
}

export function expireStaleLeases(
  leases: readonly WorkerLeaseRow[],
  now: string
): WorkerLeasePatch[] {
  const nowMs = Date.parse(now);

  return leases.flatMap((lease) => {
    if (lease.status !== "active") {
      return [];
    }

    if (Date.parse(lease.expiresAt) > nowMs) {
      return [];
    }

    return [
      {
        leaseId: lease.id,
        taskId: lease.taskId,
        workerId: lease.workerId,
        previousStatus: lease.status,
        status: "expired",
        releasedAt: now,
        releaseReason: "lease_timeout"
      }
    ];
  });
}

export function releaseActiveLeasesForTasks(
  leases: readonly WorkerLeaseRow[],
  taskIds: ReadonlySet<string>,
  now: string,
  releaseReason: string
): WorkerLeasePatch[] {
  return leases.flatMap((lease) => {
    if (lease.status !== "active" || !taskIds.has(lease.taskId)) {
      return [];
    }

    return [
      {
        leaseId: lease.id,
        taskId: lease.taskId,
        workerId: lease.workerId,
        previousStatus: lease.status,
        status: "released",
        releasedAt: now,
        releaseReason
      }
    ];
  });
}

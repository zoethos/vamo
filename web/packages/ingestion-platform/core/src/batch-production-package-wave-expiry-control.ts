/**
 * Expired production package-wave release (IP-18.6.3).
 *
 * Marks overdue approved waves expired, releases wave items, and restores queue
 * rows to staging_canary_succeeded. Control-plane only — never touches the
 * consumer production inbox.
 */

import { Client, type QueryResult } from "pg";

import type { BatchControlActor } from "./batch-control-actor.js";

export interface BatchProductionPackageWaveExpiryPgClientLike {
  query<T extends Record<string, unknown> = Record<string, unknown>>(
    sql: string,
    values?: unknown[]
  ): Promise<QueryResult<T>>;
}

export interface ReleaseExpiredProductionPackageWavesInput {
  connectionString?: string;
  client?: BatchProductionPackageWaveExpiryPgClientLike;
  projectKey?: string;
  waveKey?: string;
  actor: BatchControlActor;
  reason?: string;
  now?: string;
}

export interface ReleasedExpiredProductionPackageWave {
  waveId: string;
  waveKey: string;
  unitKeys: string[];
  auditId: string | null;
  idempotentReplay: boolean;
}

export interface ReleaseExpiredProductionPackageWavesResult {
  ok: true;
  released: ReleasedExpiredProductionPackageWave[];
}

interface ExpiredWaveRow extends Record<string, unknown> {
  id: string;
  waveKey: string;
  status: string;
  batchPlanId: string;
}

interface UnitRow extends Record<string, unknown> {
  unitKey: string;
}

export async function releaseExpiredProductionPackageWaves(
  input: ReleaseExpiredProductionPackageWavesInput
): Promise<ReleaseExpiredProductionPackageWavesResult> {
  const { client, ownedClient } = await openClient(input.client, input.connectionString);
  const now = input.now ?? new Date().toISOString();
  const reason =
    input.reason?.trim() ||
    "Release expired production package-wave approvals back to staging_canary_succeeded.";

  try {
    const values: unknown[] = [now];
    const projectFilter = input.projectKey?.trim()
      ? `and p.project_key = $${values.length + 1}`
      : "";
    if (input.projectKey?.trim()) {
      values.push(input.projectKey.trim());
    }
    const waveFilter = input.waveKey?.trim()
      ? `and w.wave_key = $${values.length + 1}`
      : "";
    if (input.waveKey?.trim()) {
      values.push(input.waveKey.trim());
    }
    const statusFilter = input.waveKey?.trim()
      ? `w.status in ('approved', 'expired')`
      : `w.status = 'approved'`;

    const candidates = await client.query<ExpiredWaveRow>(
      `
        select
          w.id::text as id,
          w.wave_key as "waveKey",
          w.status,
          w.batch_plan_id::text as "batchPlanId"
        from ingestion_platform.ingestion_batch_production_package_waves w
        join ingestion_platform.ingestion_batch_plans bp on bp.id = w.batch_plan_id
        join ingestion_platform.ingestion_projects p on p.id = bp.project_id
        where w.approval_expires_at < $1::timestamptz
          and ${statusFilter}
          ${projectFilter}
          ${waveFilter}
        order by w.approval_expires_at asc, w.id asc
      `,
      values
    );

    const released: ReleasedExpiredProductionPackageWave[] = [];

    for (const wave of candidates.rows) {
      const result = await releaseSingleExpiredWave(client, {
        wave,
        actor: input.actor,
        reason,
        now
      });
      released.push(result);
    }

    return { ok: true, released };
  } finally {
    await closeClient(ownedClient);
  }
}

async function releaseSingleExpiredWave(
  client: BatchProductionPackageWaveExpiryPgClientLike,
  input: {
    wave: ExpiredWaveRow;
    actor: BatchControlActor;
    reason: string;
    now: string;
  }
): Promise<ReleasedExpiredProductionPackageWave> {
  await client.query("begin");
  await client.query("set local statement_timeout = '10s'");

  try {
    const locked = await client.query<ExpiredWaveRow>(
      `
        select id::text as id, wave_key as "waveKey", status, batch_plan_id::text as "batchPlanId"
        from ingestion_platform.ingestion_batch_production_package_waves
        where id = $1::bigint
        for update
      `,
      [input.wave.id]
    );
    const row = locked.rows[0];
    if (!row) {
      throw new Error(`Production package wave ${input.wave.id} disappeared during expiry release.`);
    }

    if (row.status === "expired") {
      const units = await loadWaveUnitKeys(client, row.id);
      await client.query("commit");
      return {
        waveId: row.id,
        waveKey: row.waveKey,
        unitKeys: units.map((unit) => unit.unitKey),
        auditId: null,
        idempotentReplay: true
      };
    }

    if (row.status !== "approved") {
      await client.query("rollback");
      throw new Error(
        `Production package wave ${row.waveKey} is "${row.status}", not releasable as expired.`
      );
    }

    const units = await loadWaveUnitKeys(client, row.id);
    const unitKeys = units.map((unit) => unit.unitKey);

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
          'release_expired_production_package_wave',
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
        row.id,
        input.actor.type,
        input.actor.id,
        input.reason,
        JSON.stringify({
          waveKey: row.waveKey,
          unitKeys,
          releasedToQueueStatus: "staging_canary_succeeded"
        }),
        input.now
      ]
    );
    const auditId = audit.rows[0]?.id ?? null;

    await client.query(
      `
        update ingestion_platform.ingestion_batch_production_package_waves
        set status = 'expired',
            blockers = coalesce(blockers, '[]'::jsonb) || $2::jsonb,
            updated_at = $3::timestamptz
        where id = $1::bigint
      `,
      [
        row.id,
        JSON.stringify([{ code: "approval_expired", message: "Approval freshness window elapsed." }]),
        input.now
      ]
    );

    await client.query(
      `
        update ingestion_platform.ingestion_batch_production_package_wave_items
        set status = 'released',
            blockers = coalesce(blockers, '[]'::jsonb) || $2::jsonb,
            updated_at = $3::timestamptz
        where wave_id = $1::bigint
          and status = 'approved'
      `,
      [
        row.id,
        JSON.stringify([{ code: "approval_expired", message: "Wave approval expired before delivery." }]),
        input.now
      ]
    );

    if (unitKeys.length > 0) {
      const releasedQueue = await client.query(
        `
          update ingestion_platform.ingestion_batch_queue_items
          set status = 'staging_canary_succeeded',
              updated_at = $3::timestamptz
          where batch_plan_id = $1::bigint
            and unit_key = any($2::text[])
            and status = 'production_package_approved'
        `,
        [row.batchPlanId, unitKeys, input.now]
      );
      if ((releasedQueue.rowCount ?? 0) !== unitKeys.length) {
        throw new Error(
          `Expired release could not restore all queue rows (${releasedQueue.rowCount ?? 0}/${unitKeys.length}).`
        );
      }
    }

    await client.query("commit");
    return {
      waveId: row.id,
      waveKey: row.waveKey,
      unitKeys,
      auditId,
      idempotentReplay: false
    };
  } catch (error) {
    await client.query("rollback");
    throw error;
  }
}

async function loadWaveUnitKeys(
  client: BatchProductionPackageWaveExpiryPgClientLike,
  waveId: string
): Promise<UnitRow[]> {
  const result = await client.query<UnitRow>(
    `
      select unit_key as "unitKey"
      from ingestion_platform.ingestion_batch_production_package_wave_items
      where wave_id = $1::bigint
      order by run_order asc, unit_key asc
    `,
    [waveId]
  );
  return result.rows;
}

async function openClient(
  client?: BatchProductionPackageWaveExpiryPgClientLike,
  connectionString?: string
): Promise<{ client: BatchProductionPackageWaveExpiryPgClientLike; ownedClient?: Client }> {
  if (!client && !connectionString) {
    throw new Error("Production package-wave expiry release requires a server-side connection string or client.");
  }
  const ownedClient = client ? undefined : new Client({ connectionString });
  const resolved = client ?? ownedClient;
  if (!resolved) {
    throw new Error("Production package-wave expiry client could not be initialized.");
  }
  if (ownedClient) {
    await ownedClient.connect();
  }
  return { client: resolved, ownedClient };
}

async function closeClient(ownedClient?: Client): Promise<void> {
  if (ownedClient) {
    await ownedClient.end();
  }
}

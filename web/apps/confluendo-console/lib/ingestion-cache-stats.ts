import "server-only";

import { Client } from "pg";
import { createBoundedPostgresReadClientConfig } from "@confluendo/ingestion-platform/core";

// Vamo-specific cache-business metrics, read from the place-intelligence cache
// (public.location_* in the Vamo Supabase project). This is the host/consumer
// half of the dashboard data — the platform package never references these
// product tables. Server-only; never exposed to the browser.

export interface VamoCacheMetrics {
  canonicalsPromoted: number;
  observedAliases: number;
  pendingReview: number;
}

interface CacheMetricsRow {
  canonicalsPromoted: string;
  observedAliases: string;
  pendingReview: string;
}

/**
 * Returns countable cache metrics, or null when the cache DB is not configured
 * or unreachable — the dashboard then leaves those cards at zero rather than
 * failing. Telemetry-derived metrics (cache yield, calls avoided, duplicate
 * merges) are not table counts and are deferred to a usage-ledger source.
 */
export async function loadVamoCacheMetrics(): Promise<VamoCacheMetrics | null> {
  const connectionString = process.env.VAMO_PLACE_CACHE_DATABASE_URL?.trim();
  if (!connectionString) {
    return null;
  }

  const client = new Client(createBoundedPostgresReadClientConfig(connectionString));
  try {
    await client.connect();
    const result = await client.query<CacheMetricsRow>(`
      select
        (select count(*) from public.location_canonicals where promotion_state = 'promoted')::text as "canonicalsPromoted",
        (select count(*) from public.location_aliases)::text as "observedAliases",
        (select count(*) from public.location_canonicals where promotion_state = 'pending_review')::text as "pendingReview"
    `);
    const row = result.rows[0];
    return {
      canonicalsPromoted: Number(row?.canonicalsPromoted) || 0,
      observedAliases: Number(row?.observedAliases) || 0,
      pendingReview: Number(row?.pendingReview) || 0
    };
  } catch (error) {
    console.error("Vamo cache metrics read failed", error);
    return null;
  } finally {
    await client.end().catch(() => {});
  }
}

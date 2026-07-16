/**
 * Server/job-only DuckDB runner for FSQ Places Portal Iceberg (IP-18.8.16).
 *
 * Must not be imported by Console runtime. Trusted CLI/worker scripts inject this
 * runner into acquisition; the acquire adapter itself stays DuckDB-free.
 */

import {
  buildFsqPortalIcebergSelectSql,
  buildFsqPortalIcebergSetupSql,
  type FsqPortalIcebergDuckDbRunner,
  type FsqPortalIcebergQueryRow
} from "./fsq-os-places-portal-iceberg-acquire.js";

export function createDefaultFsqPortalIcebergDuckDbRunner(): FsqPortalIcebergDuckDbRunner {
  return {
    async queryCountryPlaces(input) {
      let connection: { interrupt(): void; closeSync(): void } | undefined;
      try {
        const { DuckDBInstance } = await import("@duckdb/node-api");
        const instance = await DuckDBInstance.create(":memory:");
        const duckConnection = await instance.connect();
        connection = duckConnection;

        const setup = buildFsqPortalIcebergSetupSql({
          portalAccessToken: input.portalAccessToken,
          endpoint: input.endpoint
        });
        for (const sql of setup.loadExtensionsSql) {
          await duckConnection.run(sql);
        }
        await duckConnection.run(setup.createSecretSql);
        await duckConnection.run(setup.attachSql);

        const select = buildFsqPortalIcebergSelectSql({
          table: input.table,
          countryIso: input.countryIso,
          limit: input.limit
        });

        const queryPromise = duckConnection.runAndReadAll(select.sql, {
          countryIso: select.params.countryIso,
          limit: select.params.limit
        });

        const reader = await withTimeout(queryPromise, input.timeoutMs, () => {
          duckConnection.interrupt();
        });
        if (!reader.ok) {
          void queryPromise.catch(() => undefined);
          return { ok: false, block: reader.block };
        }

        const rows: FsqPortalIcebergQueryRow[] = [];
        const rowObjects = reader.value.getRowObjectsJson();
        for (const entry of rowObjects) {
          const parsed = parseIcebergRow(entry);
          if (parsed) {
            rows.push(parsed);
          }
        }
        return { ok: true, rows };
      } catch (error) {
        return { ok: false, block: classifyPortalDuckDbError(error) };
      } finally {
        try {
          connection?.closeSync();
        } catch {
          // ignore disconnect errors
        }
      }
    }
  };
}

function parseIcebergRow(entry: unknown): FsqPortalIcebergQueryRow | null {
  if (!entry || typeof entry !== "object" || Array.isArray(entry)) {
    return null;
  }
  const row = entry as Record<string, unknown>;
  const fsqPlaceId = readString(row.fsq_place_id ?? row.fsqPlaceId);
  const name = readString(row.name);
  const latitude = readNumber(row.latitude);
  const longitude = readNumber(row.longitude);
  const countryIso = readString(row.country)?.toUpperCase();
  if (!fsqPlaceId || !name || latitude === null || longitude === null || !countryIso) {
    return null;
  }
  return {
    fsqPlaceId,
    name,
    latitude,
    longitude,
    countryIso,
    locality: readString(row.locality),
    providerCategoryIds: readStringArray(row.fsq_category_ids ?? row.fsqCategoryIds),
    providerCategoryLabels: readStringArray(row.fsq_category_labels ?? row.fsqCategoryLabels)
  };
}

function classifyPortalDuckDbError(error: unknown): string {
  const message = error instanceof Error ? error.message : String(error);
  const lower = message.toLowerCase();
  if (
    lower.includes("401") ||
    lower.includes("403") ||
    lower.includes("unauthorized") ||
    lower.includes("forbidden") ||
    lower.includes("expired") ||
    lower.includes("invalid token") ||
    lower.includes("access denied")
  ) {
    return "portal_access_token_rejected";
  }
  if (lower.includes("interrupt") || lower.includes("cancel")) {
    return "portal_query_timeout";
  }
  return "portal_query_failed";
}

async function withTimeout<T>(
  promise: Promise<T>,
  timeoutMs: number,
  onTimeout: () => void
): Promise<{ ok: true; value: T } | { ok: false; block: string }> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    const result = await Promise.race([
      promise.then((value) => ({ kind: "ok" as const, value })),
      new Promise<{ kind: "timeout" }>((resolve) => {
        timer = setTimeout(() => resolve({ kind: "timeout" }), timeoutMs);
      })
    ]);
    if (result.kind === "timeout") {
      onTimeout();
      return { ok: false, block: "portal_query_timeout" };
    }
    return { ok: true, value: result.value };
  } finally {
    if (timer) {
      clearTimeout(timer);
    }
  }
}

function readString(value: unknown): string | undefined {
  return typeof value === "string" && value.trim().length > 0 ? value.trim() : undefined;
}

function readNumber(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) {
    return value;
  }
  if (typeof value === "string" && value.trim().length > 0) {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

function readStringArray(value: unknown): string[] {
  if (!Array.isArray(value)) {
    return [];
  }
  return value
    .filter((entry): entry is string => typeof entry === "string" && entry.trim().length > 0)
    .map((entry) => entry.trim());
}

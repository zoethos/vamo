/**
 * Bounded settings for server-rendered Postgres read paths.
 *
 * The console has a short delivery deadline. These limits ensure an owned
 * database client cannot keep a request open indefinitely after that UI
 * deadline has elapsed.
 */
export const POSTGRES_READ_CONNECTION_TIMEOUT_MS = 4_000;
export const POSTGRES_READ_QUERY_TIMEOUT_MS = 4_000;
export const POSTGRES_READ_STATEMENT_TIMEOUT_MS = 4_000;

export function createBoundedPostgresReadClientConfig(connectionString: string) {
  return {
    connectionString,
    connectionTimeoutMillis: POSTGRES_READ_CONNECTION_TIMEOUT_MS,
    query_timeout: POSTGRES_READ_QUERY_TIMEOUT_MS,
    statement_timeout: POSTGRES_READ_STATEMENT_TIMEOUT_MS
  };
}

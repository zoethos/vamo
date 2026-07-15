import assert from "node:assert/strict";
import { describe, it } from "node:test";

import {
  createBoundedPostgresReadClientConfig,
  POSTGRES_READ_CONNECTION_TIMEOUT_MS,
  POSTGRES_READ_QUERY_TIMEOUT_MS,
  POSTGRES_READ_STATEMENT_TIMEOUT_MS
} from "../src/postgres-read-timeouts.js";

describe("bounded Postgres read client settings", () => {
  it("bounds connection, client-query, and server-statement waits", () => {
    assert.deepEqual(
      createBoundedPostgresReadClientConfig("postgresql://reader@example.test/control"),
      {
        connectionString: "postgresql://reader@example.test/control",
        connectionTimeoutMillis: 4_000,
        query_timeout: 4_000,
        statement_timeout: 4_000
      }
    );
    assert.equal(POSTGRES_READ_CONNECTION_TIMEOUT_MS, 4_000);
    assert.equal(POSTGRES_READ_QUERY_TIMEOUT_MS, 4_000);
    assert.equal(POSTGRES_READ_STATEMENT_TIMEOUT_MS, 4_000);
  });
});

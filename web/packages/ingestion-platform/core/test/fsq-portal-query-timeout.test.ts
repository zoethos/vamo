import assert from "node:assert/strict";
import { describe, it } from "node:test";

import {
  FSQ_PORTAL_QUERY_DEFAULT_TIMEOUT_MS,
  FSQ_PORTAL_QUERY_MAX_TIMEOUT_MS,
  FSQ_PORTAL_QUERY_MIN_TIMEOUT_MS,
  resolveFsqPortalQueryTimeoutMs
} from "../src/fsq-portal-query-timeout.js";

describe("resolveFsqPortalQueryTimeoutMs", () => {
  it("uses a five-minute bounded default for trusted Portal jobs", () => {
    assert.deepEqual(resolveFsqPortalQueryTimeoutMs(undefined), {
      ok: true,
      timeoutMs: FSQ_PORTAL_QUERY_DEFAULT_TIMEOUT_MS
    });
  });

  it("accepts an in-range explicit server-side timeout", () => {
    assert.deepEqual(resolveFsqPortalQueryTimeoutMs("600000"), {
      ok: true,
      timeoutMs: 600000
    });
  });

  it("rejects non-numeric and out-of-range values", () => {
    for (const raw of ["no", `${FSQ_PORTAL_QUERY_MIN_TIMEOUT_MS - 1}`, `${FSQ_PORTAL_QUERY_MAX_TIMEOUT_MS + 1}`]) {
      assert.deepEqual(resolveFsqPortalQueryTimeoutMs(raw), {
        ok: false,
        block: "portal_query_timeout_invalid"
      });
    }
  });
});

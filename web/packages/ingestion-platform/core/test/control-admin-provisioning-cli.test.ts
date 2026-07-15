import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, it } from "node:test";

describe("control-admin provisioning CLI", () => {
  it("defines the Supabase Auth gateway before execute-mode construction", () => {
    const source = readFileSync(
      resolve(process.cwd(), "scripts/run-control-admin-provision.mjs"),
      "utf8"
    );

    assert.ok(
      source.indexOf("class SupabaseAuthAdminGateway") < source.indexOf("new SupabaseAuthAdminGateway"),
      "execute mode must not instantiate the Auth gateway before its class declaration"
    );
  });
});

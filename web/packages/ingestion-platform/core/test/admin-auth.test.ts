import assert from "node:assert/strict";
import { describe, it } from "node:test";
import type { QueryResult } from "pg";

import {
  authorizeAdminCommand,
  authorizeAdminDashboard,
  authorizeMachineCommand,
  resolveAdminPrincipal,
  resolvePostgresAdminPrincipal,
  type AdminAuthPgClientLike,
  type AdminPrincipalRow,
  type AdminPrincipalSession
} from "../src/admin-auth.js";

describe("machine token command authorization", () => {
  it("allows non-destructive operational commands on the token path", () => {
    assert.equal(authorizeMachineCommand("start").ok, true);
    assert.equal(authorizeMachineCommand("pause").ok, true);
  });

  it("forbids destructive commands so they require an MFA admin session", () => {
    for (const command of ["reset", "shutdown"] as const) {
      const decision = authorizeMachineCommand(command);
      assert.equal(decision.ok, false);
      if (!decision.ok) {
        assert.equal(decision.code, "machine_command_forbidden");
      }
    }
  });
});

const now = "2026-06-26T12:00:00.000Z";

const viewerRow = row({ role: "viewer" });
const operatorRow = row({ role: "operator" });
const adminRow = row({ role: "admin" });

const aal1Session: AdminPrincipalSession = {
  provider: "supabase",
  providerUserId: "user-1",
  email: "founder@example.com",
  assuranceLevel: "aal1",
  hasVerifiedMfaFactor: false
};

const aal2Session: AdminPrincipalSession = {
  ...aal1Session,
  assuranceLevel: "aal2",
  hasVerifiedMfaFactor: true,
  stepUpSatisfiedAt: "2026-06-26T11:58:00.000Z"
};

describe("admin auth policy", () => {
  it("allows an active viewer to read at aal1 without an MFA factor", () => {
    const resolution = resolveAdminPrincipal({
      row: viewerRow,
      session: aal1Session,
      projectKey: "vamo",
      now
    });

    assert.equal(resolution.ok, true);
    assert.equal(authorizeAdminDashboard(resolution.principal).ok, true);
  });

  it("rejects non-allowlisted users", () => {
    const resolution = resolveAdminPrincipal({
      row: null,
      session: aal1Session,
      projectKey: "vamo",
      now
    });

    assert.deepEqual(resolution, { ok: false, code: "not_allowlisted" });
  });

  it("rejects suspended and expired rows before role checks", () => {
    const suspended = resolveAdminPrincipal({
      row: row({ role: "admin", status: "suspended" }),
      session: aal2Session,
      projectKey: "vamo",
      now
    });
    const expired = resolveAdminPrincipal({
      row: row({ role: "admin", expiresAt: "2026-06-26T11:00:00.000Z" }),
      session: aal2Session,
      projectKey: "vamo",
      now
    });

    assert.deepEqual(suspended, { ok: false, code: "suspended" });
    assert.deepEqual(expired, { ok: false, code: "expired" });
  });

  it("rejects principals outside the requested project scope", () => {
    const resolution = resolveAdminPrincipal({
      row: row({ role: "admin", scopes: ["other"] }),
      session: aal2Session,
      projectKey: "vamo",
      now
    });

    assert.deepEqual(resolution, { ok: false, code: "scope_denied" });
  });

  it("sends operators without a verified factor to enrollment", () => {
    const resolution = resolveAdminPrincipal({
      row: operatorRow,
      session: aal1Session,
      projectKey: "vamo",
      now
    });

    assert.equal(resolution.ok, true);
    assert.deepEqual(authorizeAdminDashboard(resolution.principal), {
      ok: false,
      code: "mfa_enrollment_required"
    });
  });

  it("sends operators with a factor but aal1 to challenge", () => {
    const resolution = resolveAdminPrincipal({
      row: operatorRow,
      session: { ...aal1Session, hasVerifiedMfaFactor: true },
      projectKey: "vamo",
      now
    });

    assert.equal(resolution.ok, true);
    assert.deepEqual(authorizeAdminDashboard(resolution.principal), {
      ok: false,
      code: "mfa_challenge_required"
    });
  });

  it("allows an aal2 operator to start but not reset", () => {
    const resolution = resolveAdminPrincipal({
      row: operatorRow,
      session: aal2Session,
      projectKey: "vamo",
      now
    });

    assert.equal(resolution.ok, true);
    assert.deepEqual(
      authorizeAdminCommand({
        principal: resolution.principal,
        projectKey: "vamo",
        command: "start",
        now
      }),
      { ok: true }
    );
    assert.deepEqual(
      authorizeAdminCommand({
        principal: resolution.principal,
        projectKey: "vamo",
        command: "reset",
        now
      }),
      { ok: false, code: "role_denied" }
    );
  });

  it("requires a fresh aal2 step-up for admin reset", () => {
    const oldStepUp = resolveAdminPrincipal({
      row: adminRow,
      session: { ...aal2Session, stepUpSatisfiedAt: "2026-06-26T11:20:00.000Z" },
      projectKey: "vamo",
      now
    });
    const operatorUsableStepUp = resolveAdminPrincipal({
      row: adminRow,
      session: { ...aal2Session, stepUpSatisfiedAt: "2026-06-26T11:40:00.000Z" },
      projectKey: "vamo",
      now
    });
    const freshStepUp = resolveAdminPrincipal({
      row: adminRow,
      session: aal2Session,
      projectKey: "vamo",
      now
    });

    assert.equal(oldStepUp.ok, true);
    assert.deepEqual(
      authorizeAdminCommand({
        principal: oldStepUp.principal,
        projectKey: "vamo",
        command: "reset",
        now
      }),
      { ok: false, code: "fresh_step_up_required" }
    );

    assert.equal(operatorUsableStepUp.ok, true);
    assert.deepEqual(
      authorizeAdminCommand({
        principal: operatorUsableStepUp.principal,
        projectKey: "vamo",
        command: "reset",
        now
      }),
      { ok: true }
    );

    assert.equal(freshStepUp.ok, true);
    assert.deepEqual(
      authorizeAdminCommand({
        principal: freshStepUp.principal,
        projectKey: "vamo",
        command: "reset",
        now
      }),
      { ok: true }
    );
  });

  it("looks up principals by portable provider identity without an auth.users foreign key", async () => {
    const client = new MemoryAdminAuthClient(operatorRow);

    const resolution = await resolvePostgresAdminPrincipal({
      client,
      provider: "supabase",
      providerUserId: "user-1",
      email: "founder@example.com",
      assuranceLevel: "aal2",
      hasVerifiedMfaFactor: true,
      stepUpSatisfiedAt: "2026-06-26T11:59:00.000Z",
      projectKey: "vamo",
      now
    });

    assert.equal(resolution.ok, true);
    assert.deepEqual(client.values, ["supabase", "user-1"]);
    assert.equal(resolution.principal.role, "operator");
  });
});

class MemoryAdminAuthClient implements AdminAuthPgClientLike {
  values: unknown[] = [];

  constructor(private readonly principalRow: AdminPrincipalRow | null) {}

  async query<T extends Record<string, unknown> = Record<string, unknown>>(
    _sql: string,
    values: unknown[] = []
  ): Promise<QueryResult<T>> {
    this.values = values;
    return {
      rows: this.principalRow ? [this.principalRow as unknown as T] : [],
      rowCount: this.principalRow ? 1 : 0,
      command: "SELECT",
      oid: 0,
      fields: []
    } as QueryResult<T>;
  }
}

function row(input: Partial<AdminPrincipalRow>): AdminPrincipalRow {
  return {
    provider: "supabase",
    providerUserId: "user-1",
    email: "founder@example.com",
    role: "viewer",
    scopes: ["vamo"],
    mfaRequired: true,
    status: "active",
    expiresAt: null,
    ...input
  };
}

import assert from "node:assert/strict";
import { describe, it } from "node:test";
import type { QueryResult } from "pg";

import {
  CONTROL_ADMIN_PROVISION_AUDIT_ACTION,
  provisionVamoControlAdmin,
  parseProvisionVamoControlAdminInput,
  type ControlAdminAuthGateway,
  type ControlAdminAuthUser,
  type ControlAdminProvisionPgClientLike
} from "../src/control-admin-provisioning.js";

const now = "2026-07-15T10:00:00.000Z";

describe("Vamo control-admin provisioning", () => {
  it("creates a confirmed Auth identity, exact Vamo admin grant, and audit record", async () => {
    const auth = new MemoryAuthGateway();
    const client = new MemoryProvisionClient();

    const result = await provisionVamoControlAdmin({
      authGateway: auth,
      client,
      email: " DBA.Confluendo@Outlook.com ",
      auditReason: "Provision first Vamo staging console administrator.",
      controlEnvironment: "staging",
      now
    });

    assert.deepEqual(result, {
      email: "dba.confluendo@outlook.com",
      userId: "auth-1",
      authIdentity: "created",
      grant: "created",
      role: "admin",
      projectKey: "vamo"
    });
    assert.equal(auth.createdEmails[0], "dba.confluendo@outlook.com");
    assert.equal(auth.deletedUserIds.length, 0);
    assert.deepEqual(client.principal, {
      userId: "auth-1",
      email: "dba.confluendo@outlook.com",
      role: "admin",
      scopes: ["vamo"],
      mfaRequired: true,
      status: "active"
    });
    assert.equal(client.audits.length, 1);
    assert.equal(client.audits[0]?.action, CONTROL_ADMIN_PROVISION_AUDIT_ACTION);
    assert.deepEqual(client.audits[0]?.payload, {
      email: "dba.confluendo@outlook.com",
      role: "admin",
      scopes: ["vamo"],
      controlEnvironment: "staging",
      authIdentity: "created"
    });
  });

  it("is idempotent for the same active Vamo admin grant", async () => {
    const auth = new MemoryAuthGateway({
      id: "auth-existing",
      email: "dba.confluendo@outlook.com",
      emailConfirmedAt: now
    });
    const client = new MemoryProvisionClient({
      userId: "auth-existing",
      email: "dba.confluendo@outlook.com",
      role: "admin",
      scopes: ["vamo"],
      mfaRequired: true,
      status: "active"
    });

    const result = await provisionVamoControlAdmin({
      authGateway: auth,
      client,
      email: "dba.confluendo@outlook.com",
      auditReason: "Repeat safe Vamo administrator provisioning check.",
      controlEnvironment: "staging",
      now
    });

    assert.equal(result.authIdentity, "existing");
    assert.equal(result.grant, "already_active");
    assert.equal(client.audits.length, 0);
    assert.equal(auth.createdEmails.length, 0);
  });

  it("rolls back and removes only an identity it just created when the grant conflicts", async () => {
    const auth = new MemoryAuthGateway();
    const client = new MemoryProvisionClient({
      userId: "auth-1",
      email: "dba.confluendo@outlook.com",
      role: "viewer",
      scopes: ["vamo"],
      mfaRequired: true,
      status: "active"
    });

    await assert.rejects(
      provisionVamoControlAdmin({
        authGateway: auth,
        client,
        email: "dba.confluendo@outlook.com",
        auditReason: "Attempt conflicting Vamo administrator provisioning.",
        controlEnvironment: "staging",
        now
      }),
      /conflicting control-plane grant/
    );

    assert.deepEqual(auth.deletedUserIds, ["auth-1"]);
    assert.equal(client.rolledBack, true);
  });

  it("rejects invalid requests before it reaches Auth or the control database", () => {
    assert.throws(
      () =>
        parseProvisionVamoControlAdminInput({
          email: "not-an-email",
          auditReason: "short",
          controlEnvironment: "staging",
          now
        }),
      /valid admin email/
    );
  });
});

class MemoryAuthGateway implements ControlAdminAuthGateway {
  private user: ControlAdminAuthUser | null;
  readonly createdEmails: string[] = [];
  readonly deletedUserIds: string[] = [];

  constructor(user: ControlAdminAuthUser | null = null) {
    this.user = user;
  }

  async findUserByEmail(): Promise<ControlAdminAuthUser | null> {
    return this.user;
  }

  async createConfirmedEmailUser(email: string): Promise<ControlAdminAuthUser> {
    this.createdEmails.push(email);
    this.user = { id: "auth-1", email, emailConfirmedAt: now };
    return this.user;
  }

  async deleteUser(userId: string): Promise<void> {
    this.deletedUserIds.push(userId);
  }
}

class MemoryProvisionClient implements ControlAdminProvisionPgClientLike {
  principal?: {
    userId: string;
    email: string;
    role: "admin" | "operator" | "viewer";
    scopes: string[];
    mfaRequired: boolean;
    status: "active" | "suspended";
  };
  readonly audits: Array<{ action: string; payload: Record<string, unknown> }> = [];
  rolledBack = false;

  constructor(principal?: MemoryProvisionClient["principal"]) {
    this.principal = principal;
  }

  async query<T extends Record<string, unknown> = Record<string, unknown>>(
    sql: string,
    values: unknown[] = []
  ): Promise<QueryResult<T>> {
    if (sql === "rollback") {
      this.rolledBack = true;
      return result<T>();
    }
    if (sql.includes("from ingestion_platform.ingestion_projects")) {
      return result<T>([{ id: "41" } as unknown as T]);
    }
    if (sql.includes("from ingestion_platform.ingestion_admin_principals")) {
      if (!this.principal) return result<T>();
      return result<T>([
        {
          email: this.principal.email,
          role: this.principal.role,
          scopes: this.principal.scopes,
          mfaRequired: this.principal.mfaRequired,
          status: this.principal.status
        } as unknown as T
      ]);
    }
    if (sql.includes("insert into ingestion_platform.ingestion_admin_principals")) {
      this.principal = {
        userId: String(values[0]),
        email: String(values[1]),
        role: "admin",
        scopes: [String(values[2])],
        mfaRequired: true,
        status: "active"
      };
      return result<T>();
    }
    if (sql.includes("insert into ingestion_platform.ingestion_audit_log")) {
      this.audits.push({ action: String(values[2]), payload: JSON.parse(String(values[5])) });
      return result<T>();
    }
    return result<T>();
  }
}

function result<T extends Record<string, unknown>>(rows: T[] = []): QueryResult<T> {
  return {
    command: "SELECT",
    rowCount: rows.length,
    oid: 0,
    fields: [],
    rows
  };
}

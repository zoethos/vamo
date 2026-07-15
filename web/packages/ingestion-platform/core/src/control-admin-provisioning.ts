import type { QueryResult } from "pg";

import type { AdminRole } from "./admin-auth.js";

export const VAMO_CONTROL_PROJECT_KEY = "vamo";
export const CONTROL_ADMIN_PROVISIONER_ACTOR_ID = "confluendo_control_admin_provisioner";
export const CONTROL_ADMIN_PROVISION_AUDIT_ACTION = "control.admin_principal.provisioned";

export type ControlEnvironmentName = "staging" | "production";

export interface ControlAdminAuthUser {
  id: string;
  email: string;
  emailConfirmedAt?: string | null;
}

export interface ControlAdminAuthGateway {
  findUserByEmail(email: string): Promise<ControlAdminAuthUser | null>;
  createConfirmedEmailUser(email: string): Promise<ControlAdminAuthUser>;
  deleteUser(userId: string): Promise<void>;
}

export interface ControlAdminProvisionPgClientLike {
  query<T extends Record<string, unknown> = Record<string, unknown>>(
    sql: string,
    values?: unknown[]
  ): Promise<QueryResult<T>>;
}

export interface ProvisionVamoControlAdminInput {
  authGateway: ControlAdminAuthGateway;
  client: ControlAdminProvisionPgClientLike;
  email: string;
  auditReason: string;
  controlEnvironment: ControlEnvironmentName;
  now?: string;
}

export interface ProvisionVamoControlAdminResult {
  email: string;
  userId: string;
  authIdentity: "created" | "existing";
  grant: "created" | "already_active";
  role: "admin";
  projectKey: typeof VAMO_CONTROL_PROJECT_KEY;
}

interface ProjectRow extends Record<string, unknown> {
  id: string;
}

interface PrincipalRow extends Record<string, unknown> {
  email: string;
  role: AdminRole;
  scopes: string[] | string;
  mfaRequired: boolean;
  status: "active" | "suspended";
}

interface ProvisionRequest {
  email: string;
  auditReason: string;
  controlEnvironment: ControlEnvironmentName;
  now: string;
}

/**
 * Provisions the current Vamo-only authorization model from a trusted command.
 * This is deliberately not a general customer-membership API: project-scoped
 * memberships are the post-Vamo multi-customer replacement for this path.
 */
export async function provisionVamoControlAdmin(
  input: ProvisionVamoControlAdminInput
): Promise<ProvisionVamoControlAdminResult> {
  const request = parseProvisionVamoControlAdminInput(input);
  let authUser = await input.authGateway.findUserByEmail(request.email);
  let authIdentityCreated = false;

  if (!authUser) {
    authUser = await input.authGateway.createConfirmedEmailUser(request.email);
    authIdentityCreated = true;
  }

  assertMatchingConfirmedAuthUser(authUser, request.email);

  let transactionOpen = false;
  try {
    await input.client.query("begin");
    transactionOpen = true;

    const projectResult = await input.client.query<ProjectRow>(
      `
        select id::text as id
        from ingestion_platform.ingestion_projects
        where project_key = $1
        limit 1
      `,
      [VAMO_CONTROL_PROJECT_KEY]
    );
    const project = projectResult.rows[0];
    if (!project) {
      throw new Error("The Vamo control project is not provisioned in this control database.");
    }

    const principalResult = await input.client.query<PrincipalRow>(
      `
        select
          email,
          role,
          scopes,
          mfa_required as "mfaRequired",
          status
        from ingestion_platform.ingestion_admin_principals
        where provider = 'supabase'
          and provider_user_id = $1
        for update
      `,
      [authUser.id]
    );
    const existingPrincipal = principalResult.rows[0];
    if (existingPrincipal) {
      assertExistingPrincipalMatches(existingPrincipal, request.email);
      await input.client.query("commit");
      transactionOpen = false;
      return {
        email: request.email,
        userId: authUser.id,
        authIdentity: authIdentityCreated ? "created" : "existing",
        grant: "already_active",
        role: "admin",
        projectKey: VAMO_CONTROL_PROJECT_KEY
      };
    }

    await input.client.query(
      `
        insert into ingestion_platform.ingestion_admin_principals (
          provider,
          provider_user_id,
          email,
          role,
          scopes,
          mfa_required,
          status,
          created_by_provider,
          created_by_provider_user_id
        )
        values (
          'supabase',
          $1,
          $2,
          'admin',
          array[$3]::text[],
          true,
          'active',
          'system',
          $4
        )
      `,
      [authUser.id, request.email, VAMO_CONTROL_PROJECT_KEY, CONTROL_ADMIN_PROVISIONER_ACTOR_ID]
    );

    await input.client.query(
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
        values (
          $1::bigint,
          'system',
          $2,
          $3,
          'admin_principal',
          $4,
          $5,
          $6::jsonb,
          $7::timestamptz
        )
      `,
      [
        project.id,
        CONTROL_ADMIN_PROVISIONER_ACTOR_ID,
        CONTROL_ADMIN_PROVISION_AUDIT_ACTION,
        authUser.id,
        request.auditReason,
        JSON.stringify({
          email: request.email,
          role: "admin",
          scopes: [VAMO_CONTROL_PROJECT_KEY],
          controlEnvironment: request.controlEnvironment,
          authIdentity: authIdentityCreated ? "created" : "existing"
        }),
        request.now
      ]
    );

    await input.client.query("commit");
    transactionOpen = false;
    return {
      email: request.email,
      userId: authUser.id,
      authIdentity: authIdentityCreated ? "created" : "existing",
      grant: "created",
      role: "admin",
      projectKey: VAMO_CONTROL_PROJECT_KEY
    };
  } catch (error) {
    if (transactionOpen) {
      await input.client.query("rollback").catch(() => undefined);
    }
    if (authIdentityCreated) {
      await input.authGateway.deleteUser(authUser.id).catch(() => undefined);
    }
    throw error;
  }
}

export function parseProvisionVamoControlAdminInput(
  input: Omit<ProvisionVamoControlAdminInput, "authGateway" | "client">
): ProvisionRequest {
  const email = normalizeEmail(input.email);
  if (!email || !isEmailAddress(email)) {
    throw new Error("A valid admin email is required.");
  }

  const auditReason = input.auditReason.trim();
  if (auditReason.length < 12) {
    throw new Error("An audit reason of at least 12 characters is required.");
  }

  if (input.controlEnvironment !== "staging" && input.controlEnvironment !== "production") {
    throw new Error("Control environment must be staging or production.");
  }

  const now = input.now ?? new Date().toISOString();
  if (Number.isNaN(Date.parse(now))) {
    throw new Error("Provisioning timestamp must be a valid ISO date-time.");
  }

  return { email, auditReason, controlEnvironment: input.controlEnvironment, now };
}

function assertMatchingConfirmedAuthUser(user: ControlAdminAuthUser, email: string): void {
  if (!user.id.trim()) {
    throw new Error("Supabase Auth returned an invalid user identity.");
  }
  if (normalizeEmail(user.email) !== email) {
    throw new Error("Supabase Auth returned an identity for a different email address.");
  }
  if (!user.emailConfirmedAt) {
    throw new Error("The existing Supabase Auth user has not confirmed its email address.");
  }
}

function assertExistingPrincipalMatches(principal: PrincipalRow, email: string): void {
  const sameGrant =
    normalizeEmail(principal.email) === email &&
    principal.role === "admin" &&
    principal.mfaRequired &&
    principal.status === "active" &&
    sameScopes(principal.scopes, [VAMO_CONTROL_PROJECT_KEY]);

  if (!sameGrant) {
    throw new Error(
      "This Supabase Auth identity already has a conflicting control-plane grant; use the audited access-management path instead."
    );
  }
}

function normalizeEmail(email: string): string {
  return email.trim().toLowerCase();
}

function isEmailAddress(value: string): boolean {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value);
}

function sameScopes(value: string[] | string, expected: string[]): boolean {
  const actual = Array.isArray(value) ? value : [value];
  return actual.length === expected.length && actual.every((scope) => expected.includes(scope));
}

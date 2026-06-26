import { Client, type QueryResult } from "pg";

import type { IngestionCommandKind } from "./run-state.js";

export type AdminRole = "viewer" | "operator" | "admin";
export type AdminPrincipalStatus = "active" | "suspended";
export type AdminAssuranceLevel = "aal1" | "aal2";

export type AdminAuthFailureCode =
  | "not_allowlisted"
  | "suspended"
  | "expired"
  | "scope_denied"
  | "mfa_enrollment_required"
  | "mfa_challenge_required"
  | "role_denied"
  | "fresh_step_up_required";

export interface AdminPrincipal {
  provider: "supabase" | (string & {});
  userId: string;
  email: string;
  role: AdminRole;
  scopes: string[];
  assuranceLevel: AdminAssuranceLevel;
  hasVerifiedMfaFactor: boolean;
  mfaRequired: boolean;
  stepUpSatisfiedAt?: string;
  sessionId?: string;
}

export interface AdminPrincipalRow {
  provider: string;
  providerUserId: string;
  email: string;
  role: AdminRole;
  scopes: string[];
  mfaRequired: boolean;
  status: AdminPrincipalStatus;
  expiresAt: string | Date | null;
}

export interface AdminPrincipalSession {
  provider: string;
  providerUserId: string;
  email: string;
  assuranceLevel: AdminAssuranceLevel;
  hasVerifiedMfaFactor: boolean;
  stepUpSatisfiedAt?: string;
  sessionId?: string;
}

export type AdminPrincipalResolution =
  | { ok: true; principal: AdminPrincipal }
  | { ok: false; code: AdminAuthFailureCode };

export interface AdminCommandAuthorizationInput {
  principal: AdminPrincipal;
  command: IngestionCommandKind;
  projectKey: string;
  now?: string;
  freshStepUpWindowMs?: number;
}

export interface AdminAuthPgClientLike {
  query<T extends Record<string, unknown> = Record<string, unknown>>(
    sql: string,
    values?: unknown[]
  ): Promise<QueryResult<T>>;
}

export interface ResolvePostgresAdminPrincipalInput extends AdminPrincipalSession {
  connectionString?: string;
  client?: AdminAuthPgClientLike;
  projectKey: string;
  now?: string;
}

interface AdminPrincipalDbRow extends Record<string, unknown> {
  provider: string;
  providerUserId: string;
  email: string;
  role: AdminRole;
  scopes: string[] | string;
  mfaRequired: boolean;
  status: AdminPrincipalStatus;
  expiresAt: string | Date | null;
}

const mutatingRoles = new Set<AdminRole>(["operator", "admin"]);
const freshStepUpWindowMs = 5 * 60 * 1000;

/**
 * Commands a non-session machine principal (the static API token) may run.
 * Destructive or high-impact commands (`reset`, `shutdown`) are deliberately
 * excluded: those require an authenticated admin session with MFA, so the token
 * can never bypass the human authorization path for them. Default-deny —
 * anything not listed here is forbidden for the token.
 */
export const MACHINE_TOKEN_COMMANDS: readonly IngestionCommandKind[] = ["start", "pause"];

export function authorizeMachineCommand(
  command: IngestionCommandKind
): { ok: true } | { ok: false; code: "machine_command_forbidden" } {
  return MACHINE_TOKEN_COMMANDS.includes(command)
    ? { ok: true }
    : { ok: false, code: "machine_command_forbidden" };
}

export async function resolvePostgresAdminPrincipal(
  input: ResolvePostgresAdminPrincipalInput
): Promise<AdminPrincipalResolution> {
  if (!input.client && !input.connectionString) {
    throw new Error("Admin principal lookup requires a server-side connection string or client.");
  }

  const ownedClient = input.client ? undefined : new Client({ connectionString: input.connectionString });
  const client = input.client ?? ownedClient;
  if (!client) {
    throw new Error("Admin principal lookup client could not be initialized.");
  }

  if (ownedClient) {
    await ownedClient.connect();
  }

  try {
    const result = await client.query<AdminPrincipalDbRow>(
      `
        select
          provider,
          provider_user_id as "providerUserId",
          email,
          role,
          scopes,
          mfa_required as "mfaRequired",
          status,
          expires_at as "expiresAt"
        from ingestion_platform.ingestion_admin_principals
        where provider = $1
          and provider_user_id = $2
        limit 1
      `,
      [input.provider, input.providerUserId]
    );

    const row = result.rows[0];
    if (!row) {
      return { ok: false, code: "not_allowlisted" };
    }

    return resolveAdminPrincipal({
      row: {
        provider: row.provider,
        providerUserId: row.providerUserId,
        email: row.email,
        role: row.role,
        scopes: normalizeScopes(row.scopes),
        mfaRequired: row.mfaRequired,
        status: row.status,
        expiresAt: row.expiresAt
      },
      session: input,
      projectKey: input.projectKey,
      now: input.now
    });
  } finally {
    if (ownedClient) {
      await ownedClient.end();
    }
  }
}

export function resolveAdminPrincipal(input: {
  row: AdminPrincipalRow | null;
  session: AdminPrincipalSession;
  projectKey: string;
  now?: string;
}): AdminPrincipalResolution {
  if (!input.row) {
    return { ok: false, code: "not_allowlisted" };
  }

  if (input.row.status !== "active") {
    return { ok: false, code: "suspended" };
  }

  if (isExpired(input.row.expiresAt, input.now)) {
    return { ok: false, code: "expired" };
  }

  const scopes = normalizeScopes(input.row.scopes);
  if (!hasProjectScope(scopes, input.projectKey)) {
    return { ok: false, code: "scope_denied" };
  }

  return {
    ok: true,
    principal: {
      provider: input.session.provider,
      userId: input.session.providerUserId,
      email: input.row.email || input.session.email,
      role: input.row.role,
      scopes,
      assuranceLevel: input.session.assuranceLevel,
      hasVerifiedMfaFactor: input.session.hasVerifiedMfaFactor,
      mfaRequired: input.row.mfaRequired,
      ...(input.session.stepUpSatisfiedAt
        ? { stepUpSatisfiedAt: input.session.stepUpSatisfiedAt }
        : {}),
      ...(input.session.sessionId ? { sessionId: input.session.sessionId } : {})
    }
  };
}

export function authorizeAdminDashboard(
  principal: AdminPrincipal
): { ok: true } | { ok: false; code: AdminAuthFailureCode } {
  if (principal.role === "viewer" || !principal.mfaRequired) {
    return { ok: true };
  }

  return requireVerifiedAal2(principal);
}

export function authorizeAdminCommand(
  input: AdminCommandAuthorizationInput
): { ok: true } | { ok: false; code: AdminAuthFailureCode } {
  const { principal, command, projectKey } = input;

  if (!hasProjectScope(principal.scopes, projectKey)) {
    return { ok: false, code: "scope_denied" };
  }

  if (!mutatingRoles.has(principal.role)) {
    return { ok: false, code: "role_denied" };
  }

  if (command === "reset" && principal.role !== "admin") {
    return { ok: false, code: "role_denied" };
  }

  const mfa = requireVerifiedAal2(principal);
  if (!mfa.ok) {
    return mfa;
  }

  if (command === "reset" && !hasFreshStepUp(input)) {
    return { ok: false, code: "fresh_step_up_required" };
  }

  return { ok: true };
}

export function adminPrincipalAuditContext(principal: AdminPrincipal): Record<string, unknown> {
  return {
    provider: principal.provider,
    providerUserId: principal.userId,
    email: principal.email,
    role: principal.role,
    scopes: principal.scopes,
    assuranceLevel: principal.assuranceLevel,
    hasVerifiedMfaFactor: principal.hasVerifiedMfaFactor
  };
}

function requireVerifiedAal2(
  principal: AdminPrincipal
): { ok: true } | { ok: false; code: AdminAuthFailureCode } {
  if (!principal.mfaRequired) {
    return { ok: true };
  }
  if (!principal.hasVerifiedMfaFactor) {
    return { ok: false, code: "mfa_enrollment_required" };
  }
  if (principal.assuranceLevel !== "aal2") {
    return { ok: false, code: "mfa_challenge_required" };
  }
  return { ok: true };
}

function hasFreshStepUp(input: AdminCommandAuthorizationInput): boolean {
  if (!input.principal.stepUpSatisfiedAt) {
    return false;
  }
  const nowMs = Date.parse(input.now ?? new Date().toISOString());
  const satisfiedMs = Date.parse(input.principal.stepUpSatisfiedAt);
  if (!Number.isFinite(nowMs) || !Number.isFinite(satisfiedMs)) {
    return false;
  }
  const windowMs = input.freshStepUpWindowMs ?? freshStepUpWindowMs;
  return nowMs - satisfiedMs >= 0 && nowMs - satisfiedMs <= windowMs;
}

function hasProjectScope(scopes: string[], projectKey: string): boolean {
  return scopes.includes("*") || scopes.includes(projectKey);
}

function isExpired(expiresAt: string | Date | null, now: string | undefined): boolean {
  if (!expiresAt) {
    return false;
  }
  const expiresMs = expiresAt instanceof Date ? expiresAt.getTime() : Date.parse(expiresAt);
  const nowMs = now ? Date.parse(now) : Date.now();
  return Number.isFinite(expiresMs) && Number.isFinite(nowMs) && expiresMs <= nowMs;
}

function normalizeScopes(scopes: string[] | string): string[] {
  if (Array.isArray(scopes)) {
    return scopes.map((scope) => scope.trim()).filter(Boolean);
  }
  return scopes
    .replace(/[{}"]/g, "")
    .split(",")
    .map((scope) => scope.trim())
    .filter(Boolean);
}

import type { DataApiPrivilege, TargetProjectSpec } from "../../../spec/src/types.js";
import type { PgClientLike } from "./postgres-dry-run.js";
import { parseTableName, type QualifiedTableName } from "./table-name.js";

export type SupabaseSecurityFindingCode =
  | "not_supabase_postgres_target"
  | "service_role_browser_exposure"
  | "target_not_server_side"
  | "browser_service_role_not_forbidden"
  | "production_writes_disabled"
  | "exposed_table_without_rls"
  | "missing_explicit_data_api_grant";

export interface SupabaseSecurityFinding {
  code: SupabaseSecurityFindingCode;
  severity: "block" | "warn";
  path?: string;
  table?: string;
  role?: string;
  privilege?: DataApiPrivilege;
  message: string;
}

export interface InspectSupabaseTargetSecurityInput {
  target: TargetProjectSpec;
  client: PgClientLike;
}

interface RlsStateRow extends Record<string, unknown> {
  rlsEnabled: boolean;
}

interface GrantRow extends Record<string, unknown> {
  hasGrant: boolean;
}

export function evaluateSupabaseTargetSpecSecurity(
  target: TargetProjectSpec
): SupabaseSecurityFinding[] {
  const findings: SupabaseSecurityFinding[] = [];

  if (target.adapter !== "supabase_postgres" || target.engine.type !== "supabase_postgres") {
    findings.push({
      code: "not_supabase_postgres_target",
      severity: "block",
      path: "adapter",
      message: "Supabase dry-run requires adapter and engine type to be supabase_postgres."
    });
  }

  if (target.engine.exposeServiceRoleToBrowser) {
    findings.push({
      code: "service_role_browser_exposure",
      severity: "block",
      path: "engine.exposeServiceRoleToBrowser",
      message: "Service-role credentials must never be exposed to browser/admin code."
    });
  }

  if (!target.security.serverSideOnly) {
    findings.push({
      code: "target_not_server_side",
      severity: "block",
      path: "security.serverSideOnly",
      message: "Supabase target credentials must stay behind a server-side boundary."
    });
  }

  if (!target.security.forbidBrowserServiceRole) {
    findings.push({
      code: "browser_service_role_not_forbidden",
      severity: "block",
      path: "security.forbidBrowserServiceRole",
      message: "Supabase target specs must explicitly forbid browser service-role exposure."
    });
  }

  if (target.security.writeMode !== "dry_run" || target.shipment.defaultMode !== "dry_run") {
    findings.push({
      code: "production_writes_disabled",
      severity: "block",
      path: "shipment.defaultMode",
      message: "Supabase/Postgres production writes stay disabled until the approval flow exists."
    });
  }

  return findings;
}

export async function inspectSupabaseTargetSecurity(
  input: InspectSupabaseTargetSecurityInput
): Promise<SupabaseSecurityFinding[]> {
  const specFindings = evaluateSupabaseTargetSpecSecurity(input.target);
  if (hasBlockingSupabaseSecurityFindings(specFindings)) {
    return specFindings;
  }

  const findings: SupabaseSecurityFinding[] = [];
  const exposedSchemas = new Set(input.target.security.exposedSchemas);

  for (const tableSpec of input.target.shipment.tables) {
    const qualified = parseTableName(tableSpec.table);
    if (!exposedSchemas.has(qualified.schema)) {
      continue;
    }

    const rlsState = await readRlsState(input.client, qualified);
    if (!rlsState) {
      continue;
    }

    if (input.target.security.requireRlsOnExposedSchemas && !rlsState.rlsEnabled) {
      findings.push({
        code: "exposed_table_without_rls",
        severity: "block",
        table: qualified.displayName,
        path: "security.requireRlsOnExposedSchemas",
        message: `Exposed Supabase table "${qualified.displayName}" must have row level security enabled.`
      });
    }

    if (input.target.security.requireExplicitDataApiGrants) {
      for (const role of input.target.security.dataApiRoles) {
        for (const privilege of input.target.security.dataApiPrivileges) {
          const hasGrant = await hasExplicitTableGrant(input.client, qualified, role, privilege);
          if (!hasGrant) {
            findings.push({
              code: "missing_explicit_data_api_grant",
              severity: "block",
              table: qualified.displayName,
              role,
              privilege,
              path: "security.dataApiRoles",
              message: `Role "${role}" needs explicit ${privilege.toUpperCase()} on "${qualified.displayName}" for Supabase Data API exposure.`
            });
          }
        }
      }
    }
  }

  return [...specFindings, ...findings];
}

export function hasBlockingSupabaseSecurityFindings(
  findings: SupabaseSecurityFinding[]
): boolean {
  return findings.some((finding) => finding.severity === "block");
}

async function readRlsState(
  client: PgClientLike,
  qualified: QualifiedTableName
): Promise<RlsStateRow | undefined> {
  const result = await client.query<RlsStateRow>(
    `
      select c.relrowsecurity as "rlsEnabled"
      from pg_catalog.pg_class c
      join pg_catalog.pg_namespace n on n.oid = c.relnamespace
      where n.nspname = $1
        and c.relname = $2
        and c.relkind in ('r', 'p')
    `,
    [qualified.schema, qualified.table]
  );

  return result.rows[0];
}

async function hasExplicitTableGrant(
  client: PgClientLike,
  qualified: QualifiedTableName,
  role: string,
  privilege: DataApiPrivilege
): Promise<boolean> {
  const result = await client.query<GrantRow>(
    `
      select exists (
        select 1
        from information_schema.role_table_grants
        where table_schema = $1
          and table_name = $2
          and grantee = $3
          and privilege_type = $4
      ) as "hasGrant"
    `,
    [qualified.schema, qualified.table, role, privilege.toUpperCase()]
  );

  return result.rows[0]?.hasGrant === true;
}

const CONFIRM_DISPOSABLE_TEST_DATABASE = "CONFIRM_DISPOSABLE_TEST_DB";
const REMOTE_HOST_ALLOWLIST = "INGESTION_TEST_DATABASE_HOST_ALLOWLIST";
const DISPOSABLE_LOCAL_PORT = "55433";
const LIVE_DATABASE_ENVIRONMENT_KEYS = [
  "INGESTION_CONTROL_DATABASE_URL",
  "INGESTION_CONTROL_OWNER_DATABASE_URL",
  "VAMO_STAGING_CANARY_APP_DATABASE_URL",
  "VAMO_PRODUCTION_INBOX_DATABASE_URL",
  "VAMO_PRODUCTION_INBOX_APPLY_DATABASE_URL",
  "VAMO_PRODUCTION_INBOX_TELEMETRY_DATABASE_URL"
] as const;

/**
 * Resolves the test-only database URL before a smoke suite can issue destructive
 * schema resets. Remote databases require a deliberate, exact-host opt-in.
 */
export function resolveDisposableTestDatabaseUrl(
  connectionString: string | undefined,
  environment: NodeJS.ProcessEnv = process.env
): string | undefined {
  if (!connectionString) {
    return undefined;
  }

  const databaseUrl = parsePostgresUrl(connectionString);
  const hostname = databaseUrl.hostname.toLowerCase();

  if (matchesConfiguredLiveDatabase(connectionString, environment)) {
    throw new Error(
      "INGESTION_TEST_DATABASE_URL matches a configured live control or Vamo database URL and is refused."
    );
  }

  if (isLocalhost(hostname) && databaseUrl.port === DISPOSABLE_LOCAL_PORT) {
    return connectionString;
  }

  const allowlistedHosts = parseHostAllowlist(environment[REMOTE_HOST_ALLOWLIST]);
  if (
    environment[CONFIRM_DISPOSABLE_TEST_DATABASE] !== "YES" ||
    !allowlistedHosts.has(hostname)
  ) {
    throw new Error(
      "INGESTION_TEST_DATABASE_URL is refused. Use localhost, 127.0.0.1, or ::1 on port 55433, or set CONFIRM_DISPOSABLE_TEST_DB=YES and add the exact host to INGESTION_TEST_DATABASE_HOST_ALLOWLIST only for a disposable test database."
    );
  }

  return connectionString;
}

export type DisposableTestDatabaseClient = {
  query(sql: string, values?: readonly unknown[]): Promise<unknown>;
};

export type DisposableTestDatabaseReset = {
  schemas?: readonly string[];
  roles?: readonly string[];
  ownedRoles?: readonly string[];
  tables?: readonly { schema: string; name: string }[];
  functions?: readonly { schema: string; name: string; arguments: string }[];
  roleRevocations?: readonly { grantedRole: string; memberRole: string }[];
};

/**
 * The sole owner of destructive test-database reset SQL. Every operation
 * revalidates the DSN before changing a schema, role, table, or function.
 */
export async function resetDisposableTestDatabase(
  client: DisposableTestDatabaseClient,
  connectionString: string,
  reset: DisposableTestDatabaseReset
): Promise<void> {
  resolveDisposableTestDatabaseUrl(connectionString);

  for (const schema of reset.schemas ?? []) {
    await client.query(`drop schema if exists ${quoteIdentifier(schema)} cascade`);
  }
  for (const functionRef of reset.functions ?? []) {
    await client.query(
      `drop function if exists ${quoteIdentifier(functionRef.schema)}.${quoteIdentifier(functionRef.name)}(${functionRef.arguments}) cascade`
    );
  }
  for (const table of reset.tables ?? []) {
    await client.query(
      `drop table if exists ${quoteIdentifier(table.schema)}.${quoteIdentifier(table.name)} cascade`
    );
  }
  for (const revocation of reset.roleRevocations ?? []) {
    const grantedRole = quoteIdentifier(revocation.grantedRole);
    const memberRole = quoteIdentifier(revocation.memberRole);
    await client.query(`
      do $$
      begin
        if exists (select 1 from pg_roles where rolname = '${revocation.grantedRole}')
          and exists (select 1 from pg_roles where rolname = '${revocation.memberRole}') then
          revoke ${grantedRole} from ${memberRole};
        end if;
      end;
      $$
    `);
  }
  for (const role of reset.ownedRoles ?? []) {
    const quotedRole = quoteIdentifier(role);
    await client.query(`
      do $$
      begin
        if exists (select 1 from pg_roles where rolname = '${role}') then
          drop owned by ${quotedRole};
        end if;
      end;
      $$
    `);
  }
  for (const role of reset.roles ?? []) {
    await client.query(`drop role if exists ${quoteIdentifier(role)}`);
  }
}

export async function deleteDisposableTestRow(
  client: DisposableTestDatabaseClient,
  connectionString: string,
  input: { schema: string; table: string; column: string; value: string }
): Promise<void> {
  resolveDisposableTestDatabaseUrl(connectionString);
  await client.query(
    `delete from ${quoteIdentifier(input.schema)}.${quoteIdentifier(input.table)} where ${quoteIdentifier(input.column)} = $1`,
    [input.value]
  );
}

function parsePostgresUrl(connectionString: string): URL {
  try {
    const parsed = new URL(connectionString);
    if (parsed.protocol !== "postgres:" && parsed.protocol !== "postgresql:") {
      throw new Error();
    }
    return parsed;
  } catch {
    throw new Error("INGESTION_TEST_DATABASE_URL must be a valid PostgreSQL connection string.");
  }
}

function isLocalhost(hostname: string): boolean {
  return hostname === "localhost" || hostname === "127.0.0.1" || hostname === "[::1]";
}

function quoteIdentifier(identifier: string): string {
  if (!/^[a-z_][a-z0-9_]*$/i.test(identifier)) {
    throw new Error("Disposable test reset received an unsafe SQL identifier.");
  }
  return `"${identifier}"`;
}

function parseHostAllowlist(value: string | undefined): Set<string> {
  return new Set(
    (value ?? "")
      .split(",")
      .map((entry) => entry.trim().toLowerCase())
      .filter(Boolean)
  );
}

function matchesConfiguredLiveDatabase(
  testConnectionString: string,
  environment: NodeJS.ProcessEnv
): boolean {
  const normalizedTestUrl = normalizeConnectionString(testConnectionString);
  return LIVE_DATABASE_ENVIRONMENT_KEYS.some((key) => {
    const configuredUrl = environment[key];
    return configuredUrl ? normalizeConnectionString(configuredUrl) === normalizedTestUrl : false;
  });
}

function normalizeConnectionString(connectionString: string): string {
  const parsed = parsePostgresUrl(connectionString);
  parsed.hash = "";
  parsed.search = "";
  return parsed.toString();
}

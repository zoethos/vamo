const RUNTIME_ROLE_NAME = "confluendo_app";

export function assertConfluendoControlRuntimeDatabaseUrl(connectionString: string): void {
  const username = parseDatabaseUsername(connectionString);
  if (username === RUNTIME_ROLE_NAME || username.startsWith(`${RUNTIME_ROLE_NAME}.`)) {
    return;
  }

  throw new Error(
    "INGESTION_CONTROL_DATABASE_URL must use the confluendo_app runtime role, not a postgres owner role."
  );
}

export function deriveConfluendoControlRuntimeDatabaseUrl(
  ownerConnectionString: string,
  password: string
): string {
  const ownerUrl = parseDatabaseUrl(ownerConnectionString);
  const ownerUsername = decodeURIComponent(ownerUrl.username);
  if (ownerUsername !== "postgres" && !ownerUsername.startsWith("postgres.")) {
    throw new Error("The owner control-DB URL must authenticate as a postgres owner role.");
  }

  const projectRef = deriveSupabaseProjectRef(ownerUrl, ownerUsername);
  ownerUrl.username = `${RUNTIME_ROLE_NAME}.${projectRef}`;
  ownerUrl.password = password;
  return ownerUrl.toString();
}

function parseDatabaseUsername(connectionString: string): string {
  return decodeURIComponent(parseDatabaseUrl(connectionString).username);
}

function parseDatabaseUrl(connectionString: string): URL {
  try {
    const url = new URL(connectionString);
    if ((url.protocol !== "postgres:" && url.protocol !== "postgresql:") || !url.username) {
      throw new Error();
    }
    return url;
  } catch {
    throw new Error("The control database URL must be a valid PostgreSQL connection string with a username.");
  }
}

function deriveSupabaseProjectRef(url: URL, username: string): string {
  const poolerMatch = /^postgres\.([a-z0-9]+)$/i.exec(username);
  if (poolerMatch) {
    return poolerMatch[1];
  }

  const directMatch = /^db\.([a-z0-9]+)\.supabase\.co$/i.exec(url.hostname);
  if (directMatch) {
    return directMatch[1];
  }

  throw new Error(
    "Could not derive the Supabase project reference from the owner control-DB URL. Use the owner session-pooler connection string."
  );
}

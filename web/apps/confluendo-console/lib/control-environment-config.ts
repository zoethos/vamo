import {
  parseControlEnvironment,
  type ControlEnvironment
} from "./control-environment";

export type ControlEnvironmentConfig = {
  environment: ControlEnvironment;
  supabaseUrl: string;
  supabasePublishableKey: string;
  controlDatabaseUrl: string;
  vamoPlaceCacheDatabaseUrl?: string;
  vamoProductionInboxTelemetryDatabaseUrl?: string;
  vamoProductionInboxApplyDatabaseUrl?: string;
  vamoProductionInboxWriterDatabaseUrl?: string;
  vamoProductionInboxEnvironment?: string;
  ingestionAdminApiToken?: string;
};

type Environment = Record<string, string | undefined>;

export function getDefaultControlEnvironment(environment: Environment = process.env): ControlEnvironment {
  const configured = parseControlEnvironment(environment.CONFLUENDO_CONTROL_DEFAULT_ENVIRONMENT);
  if (configured && getControlEnvironmentConfig(configured, environment)) {
    return configured;
  }
  return getControlEnvironmentConfig("production", environment) ? "production" : "staging";
}

export function getControlEnvironmentConfig(
  controlEnvironment: ControlEnvironment,
  environment: Environment = process.env
): ControlEnvironmentConfig | null {
  const prefix = `CONFLUENDO_CONTROL_${controlEnvironment.toUpperCase()}`;
  const supabaseUrl = read(environment, `${prefix}_SUPABASE_URL`);
  const supabasePublishableKey = readFirst(environment, [
    `${prefix}_SUPABASE_PUBLISHABLE_KEY`,
    `${prefix}_SUPABASE_ANON_KEY`
  ]);
  const controlDatabaseUrl = read(environment, `${prefix}_DATABASE_URL`);

  if (supabaseUrl && supabasePublishableKey && controlDatabaseUrl) {
    return {
      environment: controlEnvironment,
      supabaseUrl,
      supabasePublishableKey,
      controlDatabaseUrl,
      ...(controlEnvironment === "production"
        ? productionVamoConfig(environment, prefix)
        : {})
    };
  }

  // Existing single-environment deployments remain production-only until both
  // explicitly prefixed workspace configurations have been provisioned.
  if (controlEnvironment !== "production") {
    return null;
  }

  const legacySupabaseUrl = read(environment, "NEXT_PUBLIC_SUPABASE_URL");
  const legacySupabasePublishableKey = readFirst(environment, [
    "NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY",
    "NEXT_PUBLIC_SUPABASE_ANON_KEY"
  ]);
  const legacyControlDatabaseUrl = read(environment, "INGESTION_CONTROL_DATABASE_URL");
  if (!legacySupabaseUrl || !legacySupabasePublishableKey || !legacyControlDatabaseUrl) {
    return null;
  }

  return {
    environment: "production",
    supabaseUrl: legacySupabaseUrl,
    supabasePublishableKey: legacySupabasePublishableKey,
    controlDatabaseUrl: legacyControlDatabaseUrl,
    vamoPlaceCacheDatabaseUrl: read(environment, "VAMO_PLACE_CACHE_DATABASE_URL"),
    vamoProductionInboxTelemetryDatabaseUrl: read(
      environment,
      "VAMO_PRODUCTION_INBOX_TELEMETRY_DATABASE_URL"
    ),
    vamoProductionInboxApplyDatabaseUrl: read(
      environment,
      "VAMO_PRODUCTION_INBOX_APPLY_DATABASE_URL"
    ),
    vamoProductionInboxWriterDatabaseUrl: read(
      environment,
      "VAMO_PRODUCTION_INBOX_WRITER_DATABASE_URL"
    ),
    vamoProductionInboxEnvironment: read(environment, "VAMO_PRODUCTION_INBOX_ENVIRONMENT"),
    ingestionAdminApiToken: read(environment, "INGESTION_ADMIN_API_TOKEN")
  };
}

function productionVamoConfig(environment: Environment, prefix: string) {
  return {
    vamoPlaceCacheDatabaseUrl: read(environment, `${prefix}_VAMO_PLACE_CACHE_DATABASE_URL`),
    vamoProductionInboxTelemetryDatabaseUrl: read(
      environment,
      `${prefix}_VAMO_PRODUCTION_INBOX_TELEMETRY_DATABASE_URL`
    ),
    vamoProductionInboxApplyDatabaseUrl: read(
      environment,
      `${prefix}_VAMO_PRODUCTION_INBOX_APPLY_DATABASE_URL`
    ),
    vamoProductionInboxWriterDatabaseUrl: read(
      environment,
      `${prefix}_VAMO_PRODUCTION_INBOX_WRITER_DATABASE_URL`
    ),
    vamoProductionInboxEnvironment: read(
      environment,
      `${prefix}_VAMO_PRODUCTION_INBOX_ENVIRONMENT`
    ),
    ingestionAdminApiToken: read(environment, `${prefix}_INGESTION_ADMIN_API_TOKEN`)
  };
}

function read(environment: Environment, key: string): string | undefined {
  const value = environment[key]?.trim();
  return value || undefined;
}

function readFirst(environment: Environment, keys: string[]): string | undefined {
  for (const key of keys) {
    const value = read(environment, key);
    if (value) {
      return value;
    }
  }
  return undefined;
}

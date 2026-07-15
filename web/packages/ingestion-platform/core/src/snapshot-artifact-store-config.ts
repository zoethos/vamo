/**
 * Pure snapshot artifact store configuration for trusted job contexts (IP-18.8.12).
 */

export const SNAPSHOT_ARTIFACT_STORE_KIND_ENV = "CONFLUENDO_SNAPSHOT_ARTIFACT_STORE" as const;
export const SNAPSHOT_ARTIFACT_S3_BUCKET_ENV = "CONFLUENDO_SNAPSHOT_ARTIFACT_S3_BUCKET" as const;
export const SNAPSHOT_ARTIFACT_S3_REGION_ENV = "CONFLUENDO_SNAPSHOT_ARTIFACT_S3_REGION" as const;
export const SNAPSHOT_ARTIFACT_S3_ENDPOINT_ENV = "CONFLUENDO_SNAPSHOT_ARTIFACT_S3_ENDPOINT" as const;
export const SNAPSHOT_ARTIFACT_S3_PREFIX_ENV = "CONFLUENDO_SNAPSHOT_ARTIFACT_S3_PREFIX" as const;
export const SNAPSHOT_ARTIFACT_SUPABASE_PROJECT_REF_ENV =
  "CONFLUENDO_SNAPSHOT_ARTIFACT_SUPABASE_PROJECT_REF" as const;
export const SNAPSHOT_ARTIFACT_SUPABASE_BUCKET_ENV =
  "CONFLUENDO_SNAPSHOT_ARTIFACT_SUPABASE_BUCKET" as const;
export const SNAPSHOT_ARTIFACT_SUPABASE_REGION_ENV =
  "CONFLUENDO_SNAPSHOT_ARTIFACT_SUPABASE_REGION" as const;
export const SNAPSHOT_ARTIFACT_SUPABASE_PREFIX_ENV =
  "CONFLUENDO_SNAPSHOT_ARTIFACT_SUPABASE_PREFIX" as const;
export const SNAPSHOT_ARTIFACT_SUPABASE_ACCESS_KEY_ID_ENV =
  "CONFLUENDO_SNAPSHOT_ARTIFACT_SUPABASE_ACCESS_KEY_ID" as const;
export const SNAPSHOT_ARTIFACT_SUPABASE_SECRET_ACCESS_KEY_ENV =
  "CONFLUENDO_SNAPSHOT_ARTIFACT_SUPABASE_SECRET_ACCESS_KEY" as const;
export const LEGACY_LOCAL_ARTIFACT_STORE_DIR_ENV = "INGESTION_ARTIFACT_STORE_DIR" as const;

export type SnapshotArtifactStoreKind = "local" | "s3";
export type SnapshotArtifactStoreProvider = "generic_s3" | "supabase_storage";

export interface SnapshotArtifactStoreLocalConfig {
  kind: "local";
  baseDir: string;
}

export interface SnapshotArtifactStoreS3Config {
  kind: "s3";
  /** Explicit provider profile; omitted config literals retain generic S3 behavior. */
  provider?: SnapshotArtifactStoreProvider;
  bucket: string;
  region: string;
  endpoint?: string;
  prefix?: string;
  /** Server/job-only static credentials. Never expose this object to the browser. */
  credentials?: {
    accessKeyId: string;
    secretAccessKey: string;
  };
}

export type SnapshotArtifactStoreConfig =
  | SnapshotArtifactStoreLocalConfig
  | SnapshotArtifactStoreS3Config;

export interface SnapshotArtifactStoreJobEnv {
  [SNAPSHOT_ARTIFACT_STORE_KIND_ENV]?: string;
  [SNAPSHOT_ARTIFACT_S3_BUCKET_ENV]?: string;
  [SNAPSHOT_ARTIFACT_S3_REGION_ENV]?: string;
  [SNAPSHOT_ARTIFACT_S3_ENDPOINT_ENV]?: string;
  [SNAPSHOT_ARTIFACT_S3_PREFIX_ENV]?: string;
  [SNAPSHOT_ARTIFACT_SUPABASE_PROJECT_REF_ENV]?: string;
  [SNAPSHOT_ARTIFACT_SUPABASE_BUCKET_ENV]?: string;
  [SNAPSHOT_ARTIFACT_SUPABASE_REGION_ENV]?: string;
  [SNAPSHOT_ARTIFACT_SUPABASE_PREFIX_ENV]?: string;
  [SNAPSHOT_ARTIFACT_SUPABASE_ACCESS_KEY_ID_ENV]?: string;
  [SNAPSHOT_ARTIFACT_SUPABASE_SECRET_ACCESS_KEY_ENV]?: string;
  [LEGACY_LOCAL_ARTIFACT_STORE_DIR_ENV]?: string;
}

export interface SnapshotArtifactStoreConfigBlock {
  code: string;
  message: string;
}

export type ParseSnapshotArtifactStoreConfigResult =
  | { ok: true; config: SnapshotArtifactStoreConfig }
  | { ok: false; blocks: SnapshotArtifactStoreConfigBlock[] };

export interface ParseSnapshotArtifactStoreConfigInput {
  env: SnapshotArtifactStoreJobEnv;
  /** CLI --artifact-store-dir takes precedence over hosted S3 env. */
  preferLocalDir?: string;
  /** Hosted scheduler/job contexts require S3 instead of local dir. */
  requireHostedStore?: boolean;
}

export function parseSnapshotArtifactStoreConfig(
  input: ParseSnapshotArtifactStoreConfigInput
): ParseSnapshotArtifactStoreConfigResult {
  const preferLocalDir = readTrimmed(input.preferLocalDir);
  if (preferLocalDir) {
    if (input.requireHostedStore) {
      return blocked("hosted_local_store_forbidden", "Hosted jobs cannot use a local artifact directory.");
    }
    return { ok: true, config: { kind: "local", baseDir: preferLocalDir } };
  }

  const storeKind = readTrimmed(input.env[SNAPSHOT_ARTIFACT_STORE_KIND_ENV])?.toLowerCase();
  if (storeKind === "s3") {
    return parseS3Config(input.env);
  }
  if (storeKind === "supabase") {
    return parseSupabaseStorageConfig(input.env);
  }
  if (storeKind && storeKind !== "local") {
    return blocked(
      "artifact_store_kind_invalid",
      `${SNAPSHOT_ARTIFACT_STORE_KIND_ENV} must be "s3", "supabase", or "local".`
    );
  }

  const legacyLocalDir = readTrimmed(input.env[LEGACY_LOCAL_ARTIFACT_STORE_DIR_ENV]);
  if (legacyLocalDir) {
    if (input.requireHostedStore) {
      return blocked(
        "hosted_artifact_store_missing",
        "Hosted jobs require S3-compatible or Supabase Storage snapshot artifact configuration."
      );
    }
    return { ok: true, config: { kind: "local", baseDir: legacyLocalDir } };
  }

  if (input.requireHostedStore) {
    return blocked(
      "hosted_artifact_store_missing",
      "Hosted jobs require CONFLUENDO_SNAPSHOT_ARTIFACT_STORE=s3 or supabase with server-only credentials."
    );
  }

  return blocked(
    "artifact_store_unconfigured",
    "Configure a trusted snapshot artifact store via local directory or hosted S3 settings."
  );
}

function parseS3Config(env: SnapshotArtifactStoreJobEnv): ParseSnapshotArtifactStoreConfigResult {
  const blocks: SnapshotArtifactStoreConfigBlock[] = [];
  const bucket = readTrimmed(env[SNAPSHOT_ARTIFACT_S3_BUCKET_ENV]);
  const region = readTrimmed(env[SNAPSHOT_ARTIFACT_S3_REGION_ENV]);
  const endpoint = readTrimmed(env[SNAPSHOT_ARTIFACT_S3_ENDPOINT_ENV]);
  const prefix = normalizePrefix(readTrimmed(env[SNAPSHOT_ARTIFACT_S3_PREFIX_ENV]));

  if (!bucket) {
    blocks.push({
      code: "artifact_s3_bucket_missing",
      message: `${SNAPSHOT_ARTIFACT_S3_BUCKET_ENV} is required when ${SNAPSHOT_ARTIFACT_STORE_KIND_ENV}=s3.`
    });
  }
  if (!region) {
    blocks.push({
      code: "artifact_s3_region_missing",
      message: `${SNAPSHOT_ARTIFACT_S3_REGION_ENV} is required when ${SNAPSHOT_ARTIFACT_STORE_KIND_ENV}=s3.`
    });
  }
  if (blocks.length > 0) {
    return { ok: false, blocks };
  }

  return {
    ok: true,
    config: {
      kind: "s3",
      provider: "generic_s3",
      bucket: bucket!,
      region: region!,
      endpoint,
      prefix
    }
  };
}

function parseSupabaseStorageConfig(
  env: SnapshotArtifactStoreJobEnv
): ParseSnapshotArtifactStoreConfigResult {
  const blocks: SnapshotArtifactStoreConfigBlock[] = [];
  const projectRef = readTrimmed(env[SNAPSHOT_ARTIFACT_SUPABASE_PROJECT_REF_ENV]);
  const bucket = readTrimmed(env[SNAPSHOT_ARTIFACT_SUPABASE_BUCKET_ENV]);
  const region = readTrimmed(env[SNAPSHOT_ARTIFACT_SUPABASE_REGION_ENV]);
  const prefix = normalizePrefix(readTrimmed(env[SNAPSHOT_ARTIFACT_SUPABASE_PREFIX_ENV]));
  const accessKeyId = readTrimmed(env[SNAPSHOT_ARTIFACT_SUPABASE_ACCESS_KEY_ID_ENV]);
  const secretAccessKey = readTrimmed(env[SNAPSHOT_ARTIFACT_SUPABASE_SECRET_ACCESS_KEY_ENV]);

  if (!projectRef) {
    blocks.push({
      code: "artifact_supabase_project_ref_missing",
      message: `${SNAPSHOT_ARTIFACT_SUPABASE_PROJECT_REF_ENV} is required when ${SNAPSHOT_ARTIFACT_STORE_KIND_ENV}=supabase.`
    });
  } else if (!/^[a-z0-9]{20}$/.test(projectRef)) {
    blocks.push({
      code: "artifact_supabase_project_ref_invalid",
      message: `${SNAPSHOT_ARTIFACT_SUPABASE_PROJECT_REF_ENV} must be a 20-character lowercase Supabase project reference.`
    });
  }
  if (!bucket) {
    blocks.push({
      code: "artifact_supabase_bucket_missing",
      message: `${SNAPSHOT_ARTIFACT_SUPABASE_BUCKET_ENV} is required when ${SNAPSHOT_ARTIFACT_STORE_KIND_ENV}=supabase.`
    });
  }
  if (!region) {
    blocks.push({
      code: "artifact_supabase_region_missing",
      message: `${SNAPSHOT_ARTIFACT_SUPABASE_REGION_ENV} is required when ${SNAPSHOT_ARTIFACT_STORE_KIND_ENV}=supabase.`
    });
  }
  if (!accessKeyId) {
    blocks.push({
      code: "artifact_supabase_access_key_missing",
      message: `${SNAPSHOT_ARTIFACT_SUPABASE_ACCESS_KEY_ID_ENV} is required in the trusted job environment.`
    });
  }
  if (!secretAccessKey) {
    blocks.push({
      code: "artifact_supabase_secret_key_missing",
      message: `${SNAPSHOT_ARTIFACT_SUPABASE_SECRET_ACCESS_KEY_ENV} is required in the trusted job environment.`
    });
  }
  if (blocks.length > 0) {
    return { ok: false, blocks };
  }

  return {
    ok: true,
    config: {
      kind: "s3",
      provider: "supabase_storage",
      bucket: bucket!,
      region: region!,
      endpoint: `https://${projectRef}.storage.supabase.co/storage/v1/s3`,
      prefix,
      credentials: {
        accessKeyId: accessKeyId!,
        secretAccessKey: secretAccessKey!
      }
    }
  };
}

function normalizePrefix(value: string | undefined): string | undefined {
  if (!value) {
    return undefined;
  }
  const trimmed = value.replace(/^\/+|\/+$/g, "");
  return trimmed.length > 0 ? trimmed : undefined;
}

function blocked(code: string, message: string): ParseSnapshotArtifactStoreConfigResult {
  return { ok: false, blocks: [{ code, message }] };
}

function readTrimmed(value: string | undefined): string | undefined {
  const trimmed = value?.trim();
  return trimmed ? trimmed : undefined;
}

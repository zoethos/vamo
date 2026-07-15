/**
 * Re-export pure snapshot artifact store configuration from core (IP-18.8.12).
 */

export {
  LEGACY_LOCAL_ARTIFACT_STORE_DIR_ENV,
  SNAPSHOT_ARTIFACT_S3_BUCKET_ENV,
  SNAPSHOT_ARTIFACT_S3_ENDPOINT_ENV,
  SNAPSHOT_ARTIFACT_S3_PREFIX_ENV,
  SNAPSHOT_ARTIFACT_S3_REGION_ENV,
  SNAPSHOT_ARTIFACT_STORE_KIND_ENV,
  SNAPSHOT_ARTIFACT_SUPABASE_ACCESS_KEY_ID_ENV,
  SNAPSHOT_ARTIFACT_SUPABASE_BUCKET_ENV,
  SNAPSHOT_ARTIFACT_SUPABASE_PREFIX_ENV,
  SNAPSHOT_ARTIFACT_SUPABASE_PROJECT_REF_ENV,
  SNAPSHOT_ARTIFACT_SUPABASE_REGION_ENV,
  SNAPSHOT_ARTIFACT_SUPABASE_SECRET_ACCESS_KEY_ENV,
  parseSnapshotArtifactStoreConfig,
  type ParseSnapshotArtifactStoreConfigInput,
  type ParseSnapshotArtifactStoreConfigResult,
  type SnapshotArtifactStoreConfig,
  type SnapshotArtifactStoreConfigBlock,
  type SnapshotArtifactStoreJobEnv,
  type SnapshotArtifactStoreKind,
  type SnapshotArtifactStoreLocalConfig,
  type SnapshotArtifactStoreProvider,
  type SnapshotArtifactStoreS3Config
} from "../../../core/src/snapshot-artifact-store-config.js";

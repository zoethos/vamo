export {
  materializeArtifactBundleToScopedDir,
  type MaterializedSnapshotArtifactBundle
} from "../../../core/src/snapshot-artifact-materialize.js";
export { resolveSnapshotArtifactStoreFromJobEnv } from "./resolve-snapshot-artifact-store.js";
export {
  LEGACY_LOCAL_ARTIFACT_STORE_DIR_ENV,
  SNAPSHOT_ARTIFACT_S3_BUCKET_ENV,
  SNAPSHOT_ARTIFACT_S3_ENDPOINT_ENV,
  SNAPSHOT_ARTIFACT_S3_PREFIX_ENV,
  SNAPSHOT_ARTIFACT_S3_REGION_ENV,
  SNAPSHOT_ARTIFACT_STORE_KIND_ENV,
  parseSnapshotArtifactStoreConfig,
  type ParseSnapshotArtifactStoreConfigInput,
  type ParseSnapshotArtifactStoreConfigResult,
  type SnapshotArtifactStoreConfig,
  type SnapshotArtifactStoreConfigBlock,
  type SnapshotArtifactStoreJobEnv,
  type SnapshotArtifactStoreKind,
  type SnapshotArtifactStoreLocalConfig,
  type SnapshotArtifactStoreS3Config
} from "./snapshot-artifact-store-config.js";
export {
  buildInternalArtifactUri,
  createS3SnapshotArtifactStore,
  type CreateS3SnapshotArtifactStoreInput,
  type S3ObjectClientLike
} from "./s3-snapshot-artifact-store.js";
export {
  createSnapshotArtifactStore,
  type CreateSnapshotArtifactStoreDeps
} from "./create-snapshot-artifact-store.js";

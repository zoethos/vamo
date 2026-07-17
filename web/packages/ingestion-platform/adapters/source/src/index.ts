export {
  compareCursorValues,
  readFixtureBatch,
  type FixtureBatch,
  type FixtureSourceIssue,
  type FixtureSourceRecord,
  type ReadFixtureBatchInput
} from "./fixture-source.js";
export {
  readSnapshotBatch,
  type ReadSnapshotBatchInput,
  type SnapshotBatch,
  type SnapshotSourceIssue,
  type SnapshotSourceMetadata,
  type SnapshotSourceRecord
} from "./snapshot-source.js";
export {
  FSQ_ACQUISITION_ALLOWED_CATEGORIES,
  FSQ_ACQUISITION_ALLOWED_COUNTRIES,
  FSQ_ACQUISITION_DEFAULT_MAX_ROWS_PER_SCOPE,
  FSQ_OS_PLACES_CATALOG_SERVICE_API_KEY_ENV,
  FSQ_OS_PLACES_DEFAULT_ATTRIBUTION,
  FSQ_OS_PLACES_DEFAULT_PROVENANCE_URL,
  FSQ_OS_PLACES_PORTAL_ACCESS_TOKEN_ENV,
  FSQ_OS_PLACES_PORTAL_DEFAULT_QUERY_TIMEOUT_MS,
  FSQ_OS_PLACES_PORTAL_ICEBERG_CATALOG_ALIAS,
  FSQ_OS_PLACES_PORTAL_ICEBERG_CATEGORY_TABLE,
  FSQ_OS_PLACES_PORTAL_ICEBERG_ENDPOINT,
  FSQ_OS_PLACES_PORTAL_ICEBERG_TABLE,
  FSQ_OS_PLACES_COUNTRY_ISO,
  acquireFsqOsPlacesPortalIceberg,
  buildFsqPortalIcebergSelectSql,
  buildFsqPortalIcebergSetupSql,
  escapeSqlLiteral,
  normalizeFsqPortalPlaceRecord,
  serializeNormalizedFsqPortalRecords,
  validateFsqAcquisitionBounds,
  type FsqPortalAcquirePlan,
  type FsqPortalAcquireResult,
  type FsqPortalIcebergDuckDbRunner,
  type FsqPortalIcebergQueryRow,
  type FsqPortalPlaceRecord
} from "./fsq-os-places-portal-iceberg-acquire.js";
// DuckDB runner is intentionally NOT re-exported from this barrel so Console
// cannot pull the node-api DuckDB package through adapters/source.

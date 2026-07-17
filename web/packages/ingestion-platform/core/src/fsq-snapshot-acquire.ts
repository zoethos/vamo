/**
 * FSQ snapshot acquisition orchestration (IP-18.8.10 / IP-18.8.16).
 *
 * Composes the Portal/Iceberg provider adapter, intake validation, artifact
 * store, and optional control-plane registry registration. No consumer
 * activation writes in this slice.
 */

import type { FsqPortalAcquireResult } from "../../adapters/source/src/fsq-os-places-portal-iceberg-acquire.js";
import {
  acquireFsqOsPlacesPortalIceberg,
  FSQ_OS_PLACES_DEFAULT_ATTRIBUTION,
  FSQ_OS_PLACES_DEFAULT_PROVENANCE_URL,
  type FsqPortalIcebergDuckDbRunner,
  type FsqPortalPlaceRecord
} from "../../adapters/source/src/fsq-os-places-portal-iceberg-acquire.js";
import type { FsqSourceTaxonomyMapping } from "./fsq-source-taxonomy.js";
import { validateFsqPortalAccessTokenExpiry } from "./fsq-portal-access-token.js";
import type { SnapshotReleaseManifest } from "./snapshot-release-manifest.js";
import {
  buildSourceAcquisitionReleaseId,
  type SourceAcquisitionReleaseRecord
} from "./source-acquisition-contract.js";
import {
  computeSnapshotArtifactBundleSha256,
  createLocalSnapshotArtifactStore,
  deriveSnapshotArtifactKey,
  type SnapshotArtifactStore
} from "./snapshot-artifact-store.js";
import { registerSnapshotRelease } from "./snapshot-release-registry-control.js";
import {
  buildSnapshotIntakeArtifacts,
  intakeVersionedSnapshot,
  sha256Hex,
  type SnapshotCoverageReport,
  type SnapshotIntakeRowIssue
} from "./versioned-snapshot-intake.js";

export const FSQ_SNAPSHOT_ACQUIRE_CONFIRMATION_ENV = "CONFIRM_CONFLUENDO_FSQ_SNAPSHOT_ACQUIRE" as const;
export const FSQ_SNAPSHOT_ACQUIRE_CONFIRMATION_VALUE = "YES" as const;

export const FSQ_SNAPSHOT_DEFAULT_SOURCE_KEY = "fsq-os-places-snapshot" as const;
export const FSQ_SNAPSHOT_DEFAULT_SOURCE_PROVIDER = "fsq_os_places" as const;
export const FSQ_SNAPSHOT_DEFAULT_LICENSE = "FSQ-OS-Places" as const;
export const FSQ_SNAPSHOT_DEFAULT_RETENTION =
  "Retain until superseded by a newer approved snapshot or until source rights change." as const;

export type FsqSnapshotAcquirePreviewResult = {
  mode: "preview";
  plan: Extract<FsqPortalAcquireResult, { ok: true; preview: true }>["plan"];
  nextAction: string;
};

export type FsqSnapshotAcquireExecuteResult =
  | {
      mode: "execute";
      accepted: true;
      releaseId: string;
      artifactKey: string;
      artifactUri: string;
      bundleSha256: string;
      inputSha256: string;
      outputSha256: string;
      coverage: SnapshotCoverageReport;
      issues: SnapshotIntakeRowIssue[];
      registryAuditId?: string;
      nextAction: string;
    }
  | {
      mode: "execute";
      accepted: false;
      inputSha256: string;
      coverage: SnapshotCoverageReport;
      issues: SnapshotIntakeRowIssue[];
      blocks: string[];
      nextAction: string;
    };

export type FsqSnapshotAcquireResult =
  | { ok: false; blocks: string[] }
  | { ok: true; result: FsqSnapshotAcquirePreviewResult | FsqSnapshotAcquireExecuteResult };

export async function runFsqSnapshotAcquire(input: {
  countries: readonly string[];
  categories: readonly string[];
  maxRowsPerScope?: number;
  preview: boolean;
  confirmation?: string;
  portalAccessToken?: string;
  portalAccessTokenExpiresAt?: string;
  sourceTaxonomy?: FsqSourceTaxonomyMapping;
  acquiredAt?: string;
  artifactStoreBaseDir?: string;
  artifactStore?: SnapshotArtifactStore;
  projectKey?: string;
  controlConnectionString?: string;
  actor?: { type: string; id: string };
  auditReason?: string;
  commissionRequestId?: string;
  duckDbRunner?: FsqPortalIcebergDuckDbRunner;
  fixtureRecords?: readonly FsqPortalPlaceRecord[];
  queryTimeoutMs?: number;
  now?: string;
}): Promise<FsqSnapshotAcquireResult> {
  if (!input.preview) {
    if (input.confirmation !== FSQ_SNAPSHOT_ACQUIRE_CONFIRMATION_VALUE) {
      return { ok: false, blocks: ["confirmation_missing"] };
    }
    if (!input.portalAccessToken?.trim() && !input.fixtureRecords) {
      return { ok: false, blocks: ["portal_access_token_missing"] };
    }
    if (!input.fixtureRecords) {
      const expiry = validateFsqPortalAccessTokenExpiry({
        expiresAt: input.portalAccessTokenExpiresAt,
        now: input.now
      });
      if (!expiry.ok) {
        return { ok: false, blocks: [expiry.block] };
      }
    }
    if (!input.sourceTaxonomy && !input.fixtureRecords) {
      return { ok: false, blocks: ["source_mapping_requires_plan_refresh"] };
    }
  }

  const acquired = await acquireFsqOsPlacesPortalIceberg({
    countries: input.countries,
    categories: input.categories,
    maxRowsPerScope: input.maxRowsPerScope,
    preview: input.preview,
    portalAccessToken: input.portalAccessToken,
    portalAccessTokenExpiresAt: input.portalAccessTokenExpiresAt,
    sourceTaxonomy: input.sourceTaxonomy,
    duckDbRunner: input.duckDbRunner,
    fixtureRecords: input.fixtureRecords,
    queryTimeoutMs: input.queryTimeoutMs,
    now: input.now
  });

  if (!acquired.ok) {
    return { ok: false, blocks: acquired.blocks };
  }

  if (acquired.preview) {
    return {
      ok: true,
      result: {
        mode: "preview",
        plan: acquired.plan,
        nextAction:
          "Review bounded country/category scopes, then execute with CONFIRM_CONFLUENDO_FSQ_SNAPSHOT_ACQUIRE=YES and FSQ_OS_PLACES_PORTAL_ACCESS_TOKEN from the server/job secret store."
      }
    };
  }

  const manifest = buildAcquisitionManifest({
    inputContent: acquired.normalizedJsonl,
    acquiredAt: input.acquiredAt ?? input.now ?? new Date().toISOString()
  });
  const intake = intakeVersionedSnapshot({
    manifest,
    inputContent: acquired.normalizedJsonl,
    now: input.now
  });

  if (!intake.ok) {
    return {
      ok: false,
      blocks: intake.blocks
    };
  }

  if (!intake.accepted) {
    return {
      ok: true,
      result: {
        mode: "execute",
        accepted: false,
        inputSha256: intake.inputSha256,
        coverage: intake.coverage,
        issues: intake.issues,
        blocks: intake.blocks,
        nextAction:
          "Fix invalid, duplicate, or out-of-scope provider rows, then re-run acquisition preview before execute."
      }
    };
  }

  const releaseId = buildSourceAcquisitionReleaseId({
    sourceProvider: FSQ_SNAPSHOT_DEFAULT_SOURCE_PROVIDER,
    acquiredAt: manifest.acquiredAt,
    outputSha256: intake.release.outputSha256
  });
  const artifactKey = deriveSnapshotArtifactKey({
    sourceKey: FSQ_SNAPSHOT_DEFAULT_SOURCE_KEY,
    releaseId,
    outputSha256: intake.release.outputSha256
  });
  const artifacts = buildSnapshotIntakeArtifacts({
    release: { ...intake.release, releaseId },
    coverage: { ...intake.coverage, releaseId },
    normalizedJsonl: intake.normalizedJsonl
  });
  const artifactStore =
    input.artifactStore ??
    (input.artifactStoreBaseDir
      ? createLocalSnapshotArtifactStore(input.artifactStoreBaseDir)
      : null);
  if (!artifactStore) {
    return { ok: false, blocks: ["artifact_store_missing"] };
  }

  let stored: Awaited<ReturnType<SnapshotArtifactStore["putReleaseBundle"]>>;
  try {
    stored = await artifactStore.putReleaseBundle({
      artifactKey,
      artifacts
    });
  } catch {
    return { ok: false, blocks: ["artifact_store_write_failed"] };
  }

  let verified: boolean;
  try {
    verified = await artifactStore.verifyReleaseBundle({
      artifactKey,
      expectedBundleSha256: stored.bundleSha256
    });
  } catch {
    return { ok: false, blocks: ["artifact_store_verify_failed"] };
  }
  if (!verified) {
    return { ok: false, blocks: ["artifact_bundle_checksum_mismatch"] };
  }

  let registryAuditId: string | undefined;
  if (input.controlConnectionString && input.projectKey && input.actor && input.auditReason) {
    try {
      const registered = await registerSnapshotRelease({
        connectionString: input.controlConnectionString,
        projectKey: input.projectKey,
        release: buildRegistryReleaseRecord({
          releaseId,
          artifactKey,
          artifactUri: stored.artifactUri,
          bundleSha256: stored.bundleSha256,
          intakeRelease: intake.release,
          coverage: intake.coverage
        }),
        actor: input.actor,
        auditReason: input.auditReason,
        registrationMetadata: input.commissionRequestId
          ? { commissionRequestId: input.commissionRequestId }
          : undefined
      });
      registryAuditId = registered.auditId;
    } catch {
      return { ok: false, blocks: ["release_registration_failed"] };
    }
  }

  return {
    ok: true,
    result: {
      mode: "execute",
      accepted: true,
      releaseId,
      artifactKey,
      artifactUri: stored.artifactUri,
      bundleSha256: stored.bundleSha256,
      inputSha256: intake.inputSha256,
      outputSha256: intake.release.outputSha256,
      coverage: intake.coverage,
      issues: intake.issues,
      registryAuditId,
      nextAction: registryAuditId
        ? "Release registered as activation_ready. Binding into the consumer contract remains a separate reviewed slice."
        : "Artifacts stored locally. Provide INGESTION_CONTROL_DATABASE_URL to register the release in the control plane."
    }
  };
}

function buildAcquisitionManifest(input: {
  inputContent: string;
  acquiredAt: string;
}): SnapshotReleaseManifest {
  return {
    kind: "ingestion.snapshot_release_manifest",
    sourceKey: FSQ_SNAPSHOT_DEFAULT_SOURCE_KEY,
    sourceProvider: FSQ_SNAPSHOT_DEFAULT_SOURCE_PROVIDER,
    releaseId: "pending-intake",
    acquiredAt: input.acquiredAt,
    provenanceUrl: FSQ_OS_PLACES_DEFAULT_PROVENANCE_URL,
    sourceAttribution: FSQ_OS_PLACES_DEFAULT_ATTRIBUTION,
    licenseIdentifier: FSQ_SNAPSHOT_DEFAULT_LICENSE,
    factStorageApproved: true,
    retentionStatement: FSQ_SNAPSHOT_DEFAULT_RETENTION,
    expectedSha256: sha256Hex(input.inputContent),
    sourceFormat: "normalized_jsonl",
    intendedConsumer: "vamo",
    intendedTarget: "vamo-place-intelligence"
  };
}

function buildRegistryReleaseRecord(input: {
  releaseId: string;
  artifactKey: string;
  artifactUri: string;
  bundleSha256: string;
  intakeRelease: {
    acquiredAt: string;
    provenanceUrl: string;
    sourceAttribution: string;
    licenseIdentifier: string;
    retentionStatement: string;
    intendedConsumer: string;
    intendedTarget: string;
    inputSha256: string;
    outputSha256: string;
    rowCounts: SourceAcquisitionReleaseRecord["rowCounts"];
  };
  coverage: SnapshotCoverageReport;
}): SourceAcquisitionReleaseRecord {
  return {
    kind: "ingestion.source_acquisition_release",
    releaseId: input.releaseId,
    sourceKey: FSQ_SNAPSHOT_DEFAULT_SOURCE_KEY,
    sourceProvider: FSQ_SNAPSHOT_DEFAULT_SOURCE_PROVIDER,
    acquiredAt: input.intakeRelease.acquiredAt,
    provenanceUrl: input.intakeRelease.provenanceUrl,
    inputSha256: input.intakeRelease.inputSha256,
    outputSha256: input.intakeRelease.outputSha256,
    sourceAttribution: input.intakeRelease.sourceAttribution,
    licenseIdentifier: input.intakeRelease.licenseIdentifier,
    retentionStatement: input.intakeRelease.retentionStatement,
    intendedConsumer: input.intakeRelease.intendedConsumer,
    intendedTarget: input.intakeRelease.intendedTarget,
    artifactKey: input.artifactKey,
    artifactUri: input.artifactUri,
    status: "activation_ready",
    coverage: input.coverage,
    rowCounts: input.intakeRelease.rowCounts
  };
}

export function redactFsqSnapshotAcquireLogValue(value: string, portalAccessToken?: string): string {
  if (!portalAccessToken || portalAccessToken.length === 0) {
    return value;
  }
  return value.split(portalAccessToken).join("[REDACTED_PORTAL_ACCESS_TOKEN]");
}

export function formatFsqSnapshotAcquireLog(
  result: FsqSnapshotAcquireResult,
  portalAccessToken?: string
): string {
  const payload = JSON.stringify(result, null, 2);
  return redactFsqSnapshotAcquireLogValue(payload, portalAccessToken);
}

export { computeSnapshotArtifactBundleSha256 };

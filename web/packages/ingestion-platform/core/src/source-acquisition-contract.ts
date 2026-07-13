/**
 * Provider-neutral source acquisition release contract (IP-18.8.10).
 */

import type { SnapshotCoverageReport } from "./versioned-snapshot-intake.js";

export const SOURCE_ACQUISITION_RELEASE_KIND = "ingestion.source_acquisition_release" as const;

export const SNAPSHOT_RELEASE_STATUSES = [
  "acquired",
  "validated",
  "rejected",
  "activation_ready",
  "superseded"
] as const;

export type SnapshotReleaseStatus = (typeof SNAPSHOT_RELEASE_STATUSES)[number];

export interface SourceAcquisitionReleaseRecord {
  kind: typeof SOURCE_ACQUISITION_RELEASE_KIND;
  releaseId: string;
  sourceKey: string;
  sourceProvider: string;
  acquiredAt: string;
  provenanceUrl: string;
  inputSha256: string;
  outputSha256: string;
  sourceAttribution: string;
  licenseIdentifier: string;
  retentionStatement: string;
  intendedConsumer: string;
  intendedTarget: string;
  artifactKey: string;
  artifactUri: string;
  status: SnapshotReleaseStatus;
  coverage: SnapshotCoverageReport;
  rowCounts: {
    valid: number;
    invalid: number;
    duplicate: number;
    outOfScope: number;
  };
}

export function isSnapshotReleaseStatus(value: string): value is SnapshotReleaseStatus {
  return (SNAPSHOT_RELEASE_STATUSES as readonly string[]).includes(value);
}

export function buildSourceAcquisitionReleaseId(input: {
  sourceProvider: string;
  acquiredAt: string;
  outputSha256: string;
}): string {
  const datePart = input.acquiredAt.slice(0, 10).replace(/-/g, "");
  return `${input.sourceProvider}-${datePart}-${input.outputSha256.slice(0, 12)}`;
}

import { existsSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";

import { parseConsumerContractManifest } from "../../spec/src/consumer-contract.js";
import type {
  ConsumerDisplayFieldPresenter,
  ConsumerDisplayFieldSpec
} from "../../spec/src/types.js";
import { presentVamoPoiType } from "./vamo-place-intelligence-presentation.js";

export type { ConsumerDisplayFieldPresenter, ConsumerDisplayFieldSpec };

export interface ConsumerDisplayResolutionContext {
  scope: {
    category?: string;
    geography?: string;
    country?: string;
  };
  target: {
    key: string;
    environment: string;
  };
  source: {
    key: string;
  };
}

export interface ResolvedConsumerDisplayField {
  key: string;
  label: string;
  value: string;
  detail?: string;
}

export const VAMO_PLACE_INTELLIGENCE_QUEUE_DISPLAY_FIELDS =
  loadImportedConsumerQueueDisplayFields(
    resolveImportedConsumerManifestPath("vamo-place-intelligence"),
    "vamo/place-intelligence"
  );

export function resolveConsumerDisplayFields(
  fields: readonly ConsumerDisplayFieldSpec[] | undefined,
  context: ConsumerDisplayResolutionContext
): ResolvedConsumerDisplayField[] {
  return (fields ?? []).map((field) => {
    const rawValue = resolveDisplaySource(field.source, context);
    const detailRawValue = field.detail
      ? resolveDisplaySource(field.detail.source, context)
      : undefined;
    const detail = field.detail
      ? presentDisplayValue(detailRawValue, field.detail.presenter)
      : undefined;

    const resolved: ResolvedConsumerDisplayField = {
      key: field.key,
      label: field.label,
      value: presentDisplayValue(rawValue, field.presenter)
    };
    if (detail && detail !== "—") {
      resolved.detail = detail;
    }
    return resolved;
  });
}

export function resolveDefaultBatchQueueDisplayFields(input: {
  projectKey: string;
  targetKey: string;
}): readonly ConsumerDisplayFieldSpec[] {
  if (input.projectKey === "vamo" && input.targetKey === "vamo-place-intelligence") {
    return VAMO_PLACE_INTELLIGENCE_QUEUE_DISPLAY_FIELDS;
  }
  return [];
}

export function loadImportedConsumerQueueDisplayFields(
  manifestPath: string,
  label: string
): readonly ConsumerDisplayFieldSpec[] {
  const manifestSource = readFileSync(manifestPath, "utf8");
  const manifestResult = parseConsumerContractManifest(manifestSource);
  if (!manifestResult.ok) {
    const detail = manifestResult.errors
      .map((error) => `${error.path}: ${error.message}`)
      .join("; ");
    throw new Error(`Invalid imported consumer contract manifest for ${label}: ${detail}`);
  }
  return manifestResult.value.display?.queue?.fields ?? [];
}

function resolveImportedConsumerManifestPath(bundleKey: string): string {
  const packageRelativePath = join("fixtures", "imported", bundleKey, "manifest.yaml");
  const workspaceRelativePath = join(
    "packages",
    "ingestion-platform",
    packageRelativePath
  );
  const candidates: string[] = [];
  let dir = process.cwd();

  while (true) {
    candidates.push(join(dir, packageRelativePath));
    candidates.push(join(dir, workspaceRelativePath));

    const parent = dirname(dir);
    if (parent === dir) {
      break;
    }
    dir = parent;
  }

  const found = candidates.find((candidate) => existsSync(candidate));
  if (!found) {
    throw new Error(
      `Imported consumer contract manifest not found for ${bundleKey}. ` +
        `Checked ${candidates.length} candidate paths from ${process.cwd()}.`
    );
  }
  return found;
}

function resolveDisplaySource(
  source: string,
  context: ConsumerDisplayResolutionContext
): string | undefined {
  switch (source) {
    case "scope.category":
      return context.scope.category;
    case "scope.geography":
      return context.scope.geography;
    case "scope.country":
      return context.scope.country;
    case "source.key":
      return context.source.key;
    case "target.key":
      return context.target.key;
    case "target.environment":
      return context.target.environment;
    default:
      return undefined;
  }
}

function presentDisplayValue(
  value: string | undefined,
  presenter: ConsumerDisplayFieldPresenter | undefined
): string {
  if (!value) {
    return "—";
  }

  switch (presenter ?? "raw") {
    case "title_case":
      return titleCase(value);
    case "vamo_poi_type":
      return presentVamoPoiType(value).operatorValue;
    case "vamo_feature_type_mapping":
      return presentVamoPoiType(value).technicalMapping ?? "No consumer mapping";
    case "raw":
      return value;
    default:
      return value;
  }
}

function titleCase(value: string): string {
  return value
    .split("-")
    .filter(Boolean)
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(" ");
}
